
# 
# TODO: 23-09-04 - Replace this whole thing with a definitive solution
# 

dir_root_runs=""
dir_summaries="./run-summaries"
dir_host_lib_root=""
path_output="./run-summaries.tar.gz"

server_name=''

min_n=1
max_n=1

if [ ! -d "$dir_summaries" ]; then
    mkdir $dir_summaries
fi

for ((i=min_n; i<=max_n; i++))
do

    # Set batch execution name
    batch_name=""
    if [ "$i" -lt 10 ]; then
        batch_name="batch-0$i"
    else
        batch_name="batch-$i"
    fi
    # echo "batch_name: '$batch_name'"
    
    # Check if batch exists
    batch_dir="${dir_root_runs}/$batch_name"

    if [ ! -d "$batch_dir" ]; then
        continue
    fi
    echo "Parsing '$batch_name'..."

    for exec_id in `ls ${batch_dir}`
    do

        # Chck if it's a valid execution path
        path_exec="${batch_dir}/$exec_id"
        
        if [ ! -d "$path_exec" ]; then
            continue
        fi

        # Get execution log file
        path_exec_log="$path_exec/$exec_id.log"
        # echo "log: $path_exec_log"

        # Create summary files
        path_exec_summary_lines="$path_exec/$exec_id.summary.lines"
        path_exec_summary="$path_exec/$exec_id.summary.yml"
        
        echo "" > $path_exec_summary_lines
        echo "batch_name: $batch_name" > $path_exec_summary
        echo "server_name: $server_name" >> $path_exec_summary

        # Grab lines of interest: Execution info
        path_ref_line=`grep "^> Reference:" $path_exec_log | tail -n 1`
        path_ref=`echo "$path_ref_line" | grep -oE "'[^']+'" | awk -F"'" '{print $2}'`
        echo $path_ref_line >> $path_exec_summary_lines
        echo "path_ref: $path_ref" >> $path_exec_summary

        # 
        # TODO: 23-09-04 - Get 'si' dynamically
        # 

        # si_line=`grep "^> si:" $path_exec_log | tail -n 1`
        # si=`echo $si_line | cut -f 8 -d " "`
        # echo $si_line >> $path_exec_summary_lines
        # echo "si: $si" >> $path_exec_summary
        echo "si: 15" >> $path_exec_summary

        se_line=`grep "^> se:" $path_exec_log | tail -n 1`
        se=`echo "$se_line" | grep -oE "'[^']+'" | awk -F"'" '{print $2}'`
        echo $se_line >> $path_exec_summary_lines
        echo "se: $se" >> $path_exec_summary

        exec_id_line=`grep "^> Execution ID:" $path_exec_log | tail -n 1`
        exec_id=`echo "$exec_id_line" | grep -oE "'[^']+'" | awk -F"'" '{print $2}'`
        echo $exec_id_line >> $path_exec_summary_lines
        echo "exec_id: $exec_id" >> $path_exec_summary

        path_exec_dir_line=`grep "^> Execution Folder:" $path_exec_log | tail -n 1`
        path_exec_dir=`echo "$path_exec_dir_line" | grep -oE "'[^']+'" | awk -F"'" '{print $2}'`
        echo $path_exec_dir_line >> $path_exec_summary_lines
        echo "path_exec_dir: $path_exec_dir" >> $path_exec_summary

        lib_prefix_line=`grep "^> Lib Prefix:" $path_exec_log | tail -n 1`
        lib_prefix=`echo "$lib_prefix_line" | grep -oE "'[^']+'" | awk -F"'" '{print $2}'`
        echo $lib_prefix_line >> $path_exec_summary_lines
        echo "lib_prefix: $lib_prefix" >> $path_exec_summary

        is_degrad_search_line=`grep "^> Searching for degradation:" $path_exec_log | tail -n 1`
        is_degrad_search=`echo $is_degrad_search_line | cut -f 5 -d " "`
        echo $is_degrad_search_line >> $path_exec_summary_lines
        echo "is_degrad_search: $is_degrad_search" >> $path_exec_summary

        # Input lib
        path_input_line=`grep "^> Reads:" $path_exec_log | tail -n 1`
        path_input_img=`echo "$path_input_line" | grep -oE "'[^']+'" | awk -F"'" '{print $2}'`
        path_input_base=`echo "$path_input_img" | cut -f 7 -d "/"`
        path_input="$dir_host_lib_root/$batch_name/$path_input_base"
        echo $path_input_line >> $path_exec_summary_lines
        echo "path_input: $path_input" >> $path_exec_summary
        
        # Input size
        input_size=""

        if [ -f "$path_input" ]; then
            input_size_line=`du $path_input`
            input_size=`echo $input_size_line | cut -f 1 -d " "`
            echo $input_size_line >> $path_exec_summary_lines
        fi

        echo "input_size: $input_size" >> $path_exec_summary

        # Output size
        output_size_line=`du $path_exec | tail -n 1`
        output_size=`echo $output_size_line | cut -f 1 -d " "`
        echo $output_size_line >> $path_exec_summary_lines
        echo "output_size: $output_size" >> $path_exec_summary

        # Execution time
        exec_time_line=`grep "^Time elapsed:" $path_exec_log | tail -n 1`
        exec_time=`echo $exec_time_line | cut -f 3 -d " "`
        echo $exec_time_line >> $path_exec_summary_lines
        echo "exec_time: $exec_time" >> $path_exec_summary

        # Grab lines of interest: Number of reads
        n_read_total_line=`grep "^# Total reads" $path_exec_log | tail -n 1`
        n_read_total=`echo $n_read_total_line | cut -f 4 -d " "`
        echo $n_read_total_line >> $path_exec_summary_lines
        echo "n_read_total: $n_read_total" >> $path_exec_summary
        
        n_read_unmap_host_line=`grep "^# Reads unmapped host" $path_exec_log | tail -n 1`
        n_read_unmap_host=`echo $n_read_unmap_host_line | cut -f 5 -d " "`
        echo $n_read_unmap_host_line >> $path_exec_summary_lines
        echo "n_read_unmap_host: $n_read_unmap_host" >> $path_exec_summary

        n_read_unmap_bacter_line=`grep "^# Reads mapped bacter" $path_exec_log | tail -n 1`
        n_read_unmap_bacter=`echo $n_read_unmap_bacter_line | cut -f 5 -d " "`
        echo $n_read_unmap_bacter_line >> $path_exec_summary_lines
        echo "n_read_unmap_bacter: $n_read_unmap_bacter" >> $path_exec_summary

        n_read_preprocess_line=`grep "^# Preprocessed reads" $path_exec_log | tail -n 1`
        n_read_preprocess=`echo $n_read_preprocess_line | cut -f 4 -d " "`
        echo $n_read_preprocess_line >> $path_exec_summary_lines
        echo "n_read_preprocess: $n_read_preprocess" >> $path_exec_summary

        # Grab lines of interest: Number of contigs
        n_contig_total_line=`grep "^# Total assembled contigs" $path_exec_log | tail -n 1`
        n_contig_total=`echo $n_contig_total_line | cut -f 5 -d " "`
        echo $n_contig_total_line >> $path_exec_summary_lines
        echo "n_contig_total: $n_contig_total" >> $path_exec_summary
        
        n_contig_gt200_line=`grep "^# Contigs gt200" $path_exec_log | tail -n 1`
        n_contig_gt200=`echo $n_contig_gt200_line | cut -f 4 -d " "`
        echo $n_contig_gt200_line >> $path_exec_summary_lines
        echo "n_contig_gt200: $n_contig_gt200" >> $path_exec_summary

        n_contig_bn_hit_line=`grep "^# Number of contigs (blastN) \[hits\]" $path_exec_log | tail -n 1`
        n_contig_bn_hit=`echo $n_contig_bn_hit_line | cut -f 7 -d " "`
        echo $n_contig_bn_hit_line >> $path_exec_summary_lines
        echo "n_contig_bn_hit: $n_contig_bn_hit" >> $path_exec_summary

        n_contig_bn_viral_line=`grep "^# Number of contigs (blastN) \[viral\]" $path_exec_log | tail -n 1`
        n_contig_bn_viral=`echo $n_contig_bn_viral_line | cut -f 7 -d " "`
        echo $n_contig_bn_viral_line >> $path_exec_summary_lines
        echo "n_contig_bn_viral: $n_contig_bn_viral" >> $path_exec_summary

        n_contig_bn_non_viral_line=`grep "^# Number of contigs (blastN) \[non viral\]" $path_exec_log | tail -n 1`
        n_contig_bn_non_viral=`echo $n_contig_bn_non_viral_line | cut -f 8 -d " "`
        echo $n_contig_bn_non_viral_line >> $path_exec_summary_lines
        echo "n_contig_bn_non_viral: $n_contig_bn_non_viral" >> $path_exec_summary

        n_contig_bn_nohit_line=`grep "^# Number of contigs (blastN) \[no hits\]" $path_exec_log | tail -n 1`
        n_contig_bn_nohit=`echo $n_contig_bn_nohit_line | cut -f 8 -d " "`
        echo $n_contig_bn_nohit_line >> $path_exec_summary_lines
        echo "n_contig_bn_nohit: $n_contig_bn_nohit" >> $path_exec_summary

        n_contig_dmnd_hits_line=`grep "^# Number of contigs (diamond) \[hits\]" $path_exec_log | tail -n 1`
        n_contig_dmnd_hits=`echo $n_contig_dmnd_hits_line | cut -f 7 -d " "`
        echo $n_contig_dmnd_hits_line >> $path_exec_summary_lines
        echo "n_contig_dmnd_hits: $n_contig_dmnd_hits" >> $path_exec_summary

        n_contig_dmnd_viral_line=`grep "^# Number of contigs (diamond) \[viral\]" $path_exec_log | tail -n 1`
        n_contig_dmnd_viral=`echo $n_contig_dmnd_viral_line | cut -f 7 -d " "`
        echo $n_contig_dmnd_viral_line >> $path_exec_summary_lines
        echo "n_contig_dmnd_viral: $n_contig_dmnd_viral" >> $path_exec_summary

        n_contig_dmnd_non_viral_line=`grep "^# Number of contigs (diamond) \[non viral\]" $path_exec_log | tail -n 1`
        n_contig_dmnd_non_viral=`echo $n_contig_dmnd_non_viral_line | cut -f 8 -d " "`
        echo $n_contig_dmnd_non_viral_line >> $path_exec_summary_lines
        echo "n_contig_dmnd_non_viral: $n_contig_dmnd_non_viral" >> $path_exec_summary

        n_contig_dmnd_nohit_line=`grep "^# Number of contigs (diamond) \[no hits\]" $path_exec_log | tail -n 1`
        n_contig_dmnd_nohit=`echo $n_contig_dmnd_nohit_line | cut -f 8 -d " "`
        echo $n_contig_dmnd_nohit_line >> $path_exec_summary_lines
        echo "n_contig_dmnd_nohit: $n_contig_dmnd_nohit" >> $path_exec_summary

        n_contig_all_viral_line=`grep "^# Number of contigs (all) \[viral\]" $path_exec_log | tail -n 1`
        n_contig_all_viral=`echo $n_contig_all_viral_line | cut -f 7 -d " "`
        echo $n_contig_all_viral_line >> $path_exec_summary_lines
        echo "n_contig_all_viral: $n_contig_all_viral" >> $path_exec_summary

        n_contig_all_non_viral_line=`grep "^# Number of contigs (all) \[non viral\]" $path_exec_log | tail -n 1`
        n_contig_all_non_viral=`echo $n_contig_all_non_viral_line | cut -f 8 -d " "`
        echo $n_contig_all_non_viral_line >> $path_exec_summary_lines
        echo "n_contig_all_non_viral: $n_contig_all_non_viral" >> $path_exec_summary

        n_contig_all_nohit_line=`grep "^# Number of contigs (all) \[no hits\]" $path_exec_log | tail -n 1`
        n_contig_all_nohit=`echo $n_contig_all_nohit_line | cut -f 8 -d " "`
        echo $n_contig_all_nohit_line >> $path_exec_summary_lines
        echo "n_contig_all_nohit: $n_contig_all_nohit" >> $path_exec_summary

        # Create summary dir
        path_summary_dir="$dir_summaries/$server_name-$batch_name-$exec_id"
        # echo "path_summary_dir: '$path_summary_dir'"

        if [ ! -d "$path_summary_dir" ]; then
            mkdir $path_summary_dir
        fi

        # Copy summary files
        path_exec_csv="$path_exec/13_virus_eve_classif/$exec_id-viral-eve.csv"
        path_exec_summary_lines="$path_exec/$exec_id.summary.lines"
        path_exec_summary="$path_exec/$exec_id.summary.yml"
        path_exec_log="$path_exec/$exec_id.log"
        path_exec_log_err="$path_exec/$exec_id.err.log"

        # echo "path_exec_csv: '$path_exec_csv'"
        # echo "path_exec_summary_lines: '$path_exec_summary_lines'"
        # echo "path_exec_summary: '$path_exec_summary'"
        # echo "path_exec_log: '$path_exec_log'"
        # echo "path_exec_log_err: '$path_exec_log_err'"

        cp $path_exec_summary $path_summary_dir/
        cp $path_exec_summary_lines $path_summary_dir/
        cp $path_exec_log $path_summary_dir/
        cp $path_exec_log_err $path_summary_dir/
        
        if [ -f "$path_exec_csv" ]; then
            cp $path_exec_csv $path_summary_dir/
        fi

        # break
    done
    # break
done

echo "Creating '$path_output'..."
tar -czf $path_output $dir_summaries

echo "-- DONE --"