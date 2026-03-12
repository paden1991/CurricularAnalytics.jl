function simulate_capacity_issues(simulation, enrollment_df, total_university_cohort, major_proportion; save_path=nothing)
    println("\n--- RUNNING CAPACITY RISK ANALYSIS ---")
    
    # 1. Self-contained helper to safely clean strings
    clean_course_str(x) = replace(uppercase(strip(string(ismissing(x) ? "" : x))), r"[^A-Z0-9]" => "")
    
    # 2. Calculate the real-world size of this specific major's cohort
    real_major_cohort = total_university_cohort * major_proportion
    scale_factor = real_major_cohort / simulation.num_students
    println("Scaled simulated demand to real-world major cohort size: $(round(real_major_cohort, digits=0)) students.")

    # 3. Process historical data using YOUR exact column names
    # Step A: Sum the enrollment_cap across all sections in a single term
    term_counts = combine(groupby(enrollment_df, [:term, :course_prefix, :course_number]), :enrollment_cap => sum => :term_total_cap)
    
    # Step B: Average those term totals across all historical terms
    avg_capacity_df = combine(groupby(term_counts, [:course_prefix, :course_number]), :term_total_cap => mean => :avg_term_capacity)

    # 4. Build the Results Table
    results = DataFrame(
        Course = String[],
        Avg_Historical_Capacity = Float64[],
        Peak_Major_Demand = Float64[],
        Capacity_Consumed = String[],
        Est_Students_Shut_Out = Float64[],
        Risk_Level = String[]
    )
    
    for course in simulation.degree_plan.curriculum.courses
        p = clean_course_str(course.prefix)
        n = clean_course_str(course.num)
        
        # Match using the two split columns directly
        cap_row = filter(row -> clean_course_str(row.course_prefix) == p && clean_course_str(row.course_number) == n, avg_capacity_df)
        
        if nrow(cap_row) > 0
            avg_cap = cap_row.avg_term_capacity[1]
            
            # Find the maximum demand this major places on the course in ANY single simulated term
            peak_sim_demand = maximum(course.metadata["termenrollment"]) * scale_factor
            
            # Calculate what percentage of total university capacity this ONE major consumes
            consumed_ratio = avg_cap > 0 ? (peak_sim_demand / avg_cap) : 0.0
            
            # Estimate shut outs
            shut_out = max(0.0, peak_sim_demand - avg_cap)
            
            # Text-based risk flags
            flag = "OK"
            if consumed_ratio > 1.0
                flag = "BOTTLENECK"
            elseif consumed_ratio > 0.6
                flag = "HIGH RISK"
            end
            
            push!(results, [
                "$(course.prefix) $(course.num)", 
                round(avg_cap, digits=1), 
                round(peak_sim_demand, digits=1), 
                string(round(consumed_ratio * 100, digits=1), "%"),
                round(shut_out, digits=1),
                flag
            ])
        end
    end
    
    # Sort by the most severe bottlenecks (highest shut-outs at the top)
    sort!(results, :Est_Students_Shut_Out, rev=true)
    
    # Print the results to the console cleanly
    pretty_table(results, alignment=:l)
    
    # Export directly to CSV
    if save_path !== nothing
        CSV.write(save_path, results)
        println("\nReport successfully saved to: $save_path")
    end
    
    return results
end
