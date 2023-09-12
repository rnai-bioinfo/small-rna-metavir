skip_libs=("")
dir_root_libs=""
dir_root_runs=""

for file in `ls ${dir_root_libs}/*.fasta`
do

lib_id=`echo $file | cut -f 7 -d "/" | cut -f 1 -d "_"`
# echo "lib_id [cmd]: '${file} | cut -f 7 -d \"/\" | cut -f 1 -d \"_\"'"
# echo "lib_id: '${lib_id}'"

# Check if the current item should be skipped
should_skip=false

for should_skip_lib in "${should_skip_libs[@]}"; do
    if [[ "$lib_id" == "$should_skip_lib" ]]; then
        should_skip=true
        break
    fi
done

if [[ "$should_skip" == "true" ]]; then
    continue
fi

# Create results directory
exec_id=val-${lib_id}
dir_run=${dir_root_runs}/${exec_id}
# echo "lib_id: '${lib_id}' | exec_id: '${exec_id}' | dir_run: '${dir_run}'"

if [ ! -d "$dir_run" ]; then
    # echo mkdir $dir_run
    mkdir $dir_run
fi

# Run pipeline for the current lib
# echo "perl main.pl -fasta ${file} -hostgenome /small-rna-metavir/asset/refs/ref_hosts/refs_Aae_Aalb_Agam_culex.fasta -process 40 -si 15 -se 35 -size 20000 -exec-id ${exec_id} -prefix ${lib_id} 2> ${dir_run}/${exec_id}.err.log"
perl main.pl -fasta ${file} -hostgenome /small-rna-metavir/asset/refs/ref_hosts/refs_Aae_Aalb_Agam_culex.fasta -process 40 -si 15 -se 35 -size 20000 -exec-id ${exec_id} -prefix ${lib_id} 2> ${dir_run}/${exec_id}.err.log

done