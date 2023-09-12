use strict;
use warnings;

use Time::HiRes;
use POSIX qw(strftime);
use Getopt::Long;

#
# TODO: 2023-03-07 - Use a decent logger
# 
use constant EXEC_ROOT_DIR => "./runs";
use constant REF_BACTERIA_GENOMES => "/small-rna-metavir/asset/refs/bacterial_genomes/all_bacters.fasta";
use constant REF_BLAST_DB_NT => "/small-rna-metavir/asset/blastdb/nt";
use constant REF_DIAMOND_NR => "/small-rna-metavir/asset/diamond/nr.dmnd";
use constant PATH_CLASSIF_EVE => "/small-rna-metavir/asset/classifier/model_classif_virus_eve";

#######################################################################
### TIME HANDLERS -----------------------------------------------------
#######################################################################

sub getTimeDiff {
    my $t0 = $_[0] or die "Must provide at least one date for calculation!";
    my $t1 = $_[1];
    my $time_diff = Time::HiRes::tv_interval([$t0], [$t1]);
    return $time_diff;
}

sub getTimeStr {
    
    my $time = $_[0] or die "Must provide time";
    my $isFullDate = $_[1] // 1;
    
    my $time_ms = 1000 * ($time - int($time));
    my $dtTemplate = $isFullDate ? "%Y-%m-%d %H:%M:%S" : "%H:%M:%S";
    my $time_str = strftime($dtTemplate, localtime($time)) . sprintf ":%03d", ($time_ms);
    
    return $time_str;
}

sub getStepTimebBeginMsg {

    my $id = $_[0] or die "Must provide the execution ID!";
    my $title = $_[1] or die "Must provide step title!";
    
    my $time = getTimeStr(Time::HiRes::gettimeofday());

    return "
------------------------------------------------------
>> [$id] Begin of step '$title'

At $time...
";
}

sub getStepTimeEndMsg {

    my $id = $_[0] or die "Must provide the execution ID!";
    my $title = $_[1] or die "Must provide step title!";
    my $t0 = $_[2] or die "Must provide time 00!";
    my $t1 = $_[3] or die "Must provide time 01!";

    my $t0_str = getTimeStr($t0);
    my $t1_str = getTimeStr($t1);
    my $time_diff_str = getTimeStr(getTimeDiff($t0, $t1), 0);

    return "

>> [$id] End of step '$title'...

From '$t0_str' to '$t1_str'
Time elapsed: $time_diff_str

------------------------------------------------------
";
}

my $time_start = $^T;
my $current_time = $time_start;
my $last_time = $time_start;

my $time_diff = 0;
my $time_msg = "";

my $step_name = "";

#######################################################################
### PARSE INPUTS ------------------------------------------------------
#######################################################################

my $usage = "
------------------------------------------------------
USAGE:

$0 -fasta <reads in letter space without quality> -fastq <reads in fastq format with quality>  -qual <quality file> -fastqgz <reads in fastq format compressed gzip> [-nohostfilter]  -prefix <prefix>   -hostgenome <reference Host genome for reads filtering> -process <number of process to use> -size <expected size>  -log <log file name>
$0 -h

------------------------------------------------------
Args Description:

-fasta <reads are in fasta>    : Input reads are in fasta format without quality
-fastq <reads are in fasta>    : Input reads are in fastq format
-qual <reads .qual>            : Input quality file
-fastqgz <reads are in fastq.gz>	: Input reads are in fastq compressed as .gz format

-hostgenome <reference .fasta> : host reference genome
-size <expected size of genome>: The expected size of the genome to detect
-nohostfilter                      : Run directly the assembly without mapping to the host genome previously 

-si <size reads>	       		: Init range to use
-se <size reads>	       	    : End range to use
-hash <hash length>	       	    : hash to be used in velvet assembly

-process <number of process>   : number of process to use

-prefix <Output prefix>         : Output prefix folder name
-log <log file name>	       : log file name to storage the execution lines
-clean					: Clean large intermediate files

-h                             : Help message
";

# Required args
my $qual; # Quality file name
my $hostgenome;
my $process; # TODO: 2023-02-25 - Does 'proccess' stand for 'processors'?
my $size;

my $se;
my $si;

# Conditionally required args

#
# REVIEW: 2023-03-01 - Shall we standardize 'path' variables (prefix 'path'?)
#

my $fasta;
my $fastq;

# 
# TODO: 2023-02-25 - Check optional args
# 

# Optional args
my $fastqgz;
# my $log; # TODO: 2023-02-27 - Restablish the custom log file(s) option
my $hash;
my $clean;
my $nohostfilter;
my $large_index;
my $deg; # TODO: 2023-02-25 - Can we please call it 'degradation'?
my $help;
my $lib_prefix;
my $exec_id;

GetOptions("qual=s" => \$qual,
    "hostgenome=s" => \$hostgenome,
    "fasta=s" => \$fasta,
    "fastqgz=s" => \$fastqgz,
    "fastq=s" => \$fastq,
    "prefix=s" => \$lib_prefix,
    "size=s" => \$size,
    "hash=s" => \$hash,
    "si=s" => \$si,
    "se=s" => \$se,
    "process=s" => \$process,
    "clean!" => \$clean,
    "nohostfilter!" => \$nohostfilter, # Options must be lowcase and without "_"
    "degradation!" => \$deg,
    "largeindex!" => \$large_index,
    "h!" => \$help,
    "exec-id=s" => \$exec_id
);

if ($help) {
    die $usage;
}

if (not defined($nohostfilter) and not defined($fasta) and not defined($fastqgz)) {
    if (not(defined $fastq)) {
        if ((not(defined($fastqgz))) and(not defined($fastq)) and(not defined($fasta))) {
            die "\nGive a valid input file!\n ", $usage;
        }

        if (not(defined($qual)) and(not defined($fastq)) and(not defined($fasta))) {
            die "\nGive a valid input quality file name! \n", $usage;
        }
    }
}

if (defined($large_index)) {
    $large_index = " --large-index ";
} else {
    $large_index = " ";
}

if (not(defined($exec_id))) {
    die "\nYou must name an ID for this execution! \n", $usage;
}

if (not(defined($hostgenome))) {
    die "\nGive a valid input reference file! \n", $usage;
}

if (not(defined($size))) {
    die "\nGive the genome's expected size! \n", $usage;
}

if (not(defined($lib_prefix))) {
    die "\nGive a lib prefix! \n", $usage;
}

if (not(defined($hash))) {
    $hash = 15;
}

# my $exec_dir = strftime("exec_%Y%m%d_%H%M%S", localtime($time_start));
my $exec_dir = EXEC_ROOT_DIR . "/$exec_id";

#######################################################################
### Set running details -----------------------------------------------
#######################################################################

my $time_start_str = getTimeStr($time_start);
my $runningDetails = "

-------------------------------------------
> Details:

Start Time: $time_start_str

> Reads: '$fasta';
> Reference: '$hostgenome';
> si: '$si';
> se: '$se';
> si: '$hash';
> Execution ID: '$exec_id';
> Execution Folder: '$exec_dir';
> Lib Prefix: '$lib_prefix';
";

if (defined($deg)) {
    $runningDetails .= "> Searching for degradation: TRUE\n";
} else {
    $runningDetails .= "> Searching for degradation: FALSE\n";
}

$runningDetails .= "\n-------------------------------------------\n";

print STDOUT $runningDetails . "\n";

#######################################################################
### Define paths ------------------------------------------------------
#######################################################################

# 
# REVIEW: 2023-02-27 - Find a better way to manage file paths
# REVIEW: 2023-03-01 - Shall we standardize these directories as all other 'path' variables too? ('path' prefix?)
# 

# Step folders
my $step2		="$exec_dir/02_filter_size_gaps_convertion";
my $step3		="$exec_dir/03_mapping_vector";
my $step4		="$exec_dir/04_getUnmapped";

my $step5_1_opt	="$exec_dir/05_1_assembleUnmapped_opt";
my $step5_2_fix	="$exec_dir/05_2_assembleUnmapped_fix";
my $step5_3_opt_fix = "$exec_dir/05_3_assembleUnmapped_opt_fix";
my $step5_4_opt_20to23 = "$exec_dir/05_4_assembleUnmapped_opt_20to23";
my $step5_5_opt_24to30 = "$exec_dir/05_5_assembleUnmapped_opt_24to30";
my $step5_6_cap3  = "$exec_dir/05_6_cap3";

my $step6		="$exec_dir/06_blast";
my $step7		="$exec_dir/07_reportBlast";
my $step11		="$exec_dir/11_profiles";
my $step12		="$exec_dir/12_z_score_small_rna_features";
my $step13		="$exec_dir/13_virus_eve_classif";

# Utils scripts
my $path_utils = "/small-rna-metavir/src/utils";

my $path_warns = "$exec_dir/$exec_id.warn";

my $path_filter_diamond = "$path_utils/filter_diamond.sh";
my $path_filter_fasta_by_size = "$path_utils/filter_fasta_by_size.py";
my $path_plot_dist_per_base_by_reads = "$path_utils/plot-geral-dist-base-reads/plotGeralDistributionPerBaseByReads.pl";
my $path_merge_contigs = "$path_utils/merge-contigs/mergeContigsNew.pl";
my $path_fix_cap3_contigs = "$path_utils/fixIdCap3Contigs.pl";
my $path_filter_blast = "$path_utils/filterblast.pl";
my $path_analyse_contigs_blastn = "$path_utils/analyse-contigs-blastn/analyzeContigsFilterBlastn.pl";
my $path_extract_seqs_no_hit_blast = "$path_utils/extract-seqs/extractSequencesNoHitBlast.pl";

my $path_sam_2_sam_stranded = "$path_utils/sam-sam-stranded-counts/samToSamStrandedByCounts.pl";
my $path_z_score_both_strands = "$path_utils/z-score/virome_zscore.bothstrands.pl";
my $path_z_score_feature = "$path_utils/z-score/set_Zscore_features_matrix.R";

my $path_eve_classif = "$path_utils/viral_eve_classification.py";

my $path_plot_map_data_base_preference = "$path_utils/plot-map-base-preference/plotMappingDataPerBasePreference.pl";

#######################################################################
### Create step folders -----------------------------------------------
#######################################################################

print "Creating folders...\n\n";

if (not -e EXEC_ROOT_DIR) {
    my $cmd = "mkdir ".EXEC_ROOT_DIR;
    `$cmd`;
}
if (not -e $exec_dir) {
    `mkdir $exec_dir`;
}

if (not -e $step2) {
    `mkdir $step2`;
}
if (not -e $step3) {
    `mkdir $step3`;
}
if (not -e $step4) {
    `mkdir $step4`;
}
if (not -e $step5_1_opt) {
    `mkdir $step5_1_opt`;
}
if (not -e $step5_2_fix) {
    `mkdir $step5_2_fix`
}
if (not -e $step5_3_opt_fix) {
    `mkdir $step5_3_opt_fix`;
}
if (not -e $step5_4_opt_20to23) {
    `mkdir $step5_4_opt_20to23`;
}
if (not -e $step5_5_opt_24to30) {
    `mkdir $step5_5_opt_24to30`;
}
if (not -e $step5_6_cap3) {
    `mkdir $step5_6_cap3`;
}
if (not -e $step6) {
    `mkdir $step6`;
}
if (not -e $step7) {
    `mkdir $step7`;
}
if (not -e $step11) {
    `mkdir $step11`;
}
if (not -e $step12) {
    `mkdir $step12`;
}
if (not -e $step13) {
    `mkdir $step13`;
}

#######################################################################
### Configure logging -------------------------------------------------
#######################################################################

# 
# NOTE: From here on all printed stuff will be sent to the log file
# 

# open filehandle log.txt
my $LOG_FH;
# open($LOG_FH, ">>", PATH_LOG_MAIN) or die "Couldn't open: $!"; # $! is a special variable holding the error
open($LOG_FH, ">>", "$exec_dir/$exec_id.log") or die "Couldn't open: $!"; # $! is a special variable holding the error
*STDERR = $LOG_FH;
select $LOG_FH;

print "\n\n";
print "#######################################################################\n";
print ">> New execution";
print $runningDetails;

#######################################################################
### Execution finisher ------------------------------------------------
#######################################################################

# 
# TODO: 2023-08-31 - Do it in a better way
# 

sub finishSuccesfully {

    my $final_msg = $_[0];

    $current_time = Time::HiRes::gettimeofday();
    $time_diff = getTimeDiff($time_start, $current_time);
    my $time_elapsed_str = getTimeStr($time_diff, 0);

    my $msg_finish = "

-- THE END --
Time elapsed: $time_elapsed_str

";

    # Print final messages to log file
    if (defined($final_msg)) {
        print $final_msg;
    }
    print $msg_finish;
    close($LOG_FH);

    # Print final messages to std out
    if (defined($final_msg)) {
        print STDOUT "$final_msg \n";
    }
    print STDOUT "$msg_finish \n";
    
    exit 0;
}

#######################################################################
### Handle FASTQ sequences --------------------------------------------
#######################################################################

$step_name = "Handle FASTQ sequences";

$time_msg = getStepTimebBeginMsg($exec_id, $step_name);
print STDOUT $time_msg;
print $time_msg;

# -----------------------------------------------------------------------

my $path_02_trim_filtered_gt15_fa = "$step2/trimmed_filtered_gt15.fasta";

if (defined($fastq)) {

    my $path_02_trim_quality_fq = "$step2/${fastq}_trimmed.fastq";

	print "Processing fastq sequences...\n";
	print "\n\nRunning step 0 [ quality filter - fastq_quality_filter ]\n";
	my $exec_fq_0 = "trim_galore --fastqc --length 18 --trim-n --max_n 0 -o $step2 -j 4 --dont_gzip $fastq";

	print "\nSTEP0\n\t $exec_fq_0\n";
	`$exec_fq_0`;

    # Converting fastq to fasta
    print "\n\nRunning step 2 [ converting fastq to fasta - fastq_to_fasta ]\n";
	my $exec_fq_2="fastq_to_fasta -Q 33 -i $path_02_trim_quality_fq -o $path_02_trim_filtered_gt15_fa";
	print "\nSTEP2\n\t $exec_fq_2\n";
	`$exec_fq_2`;
}

# -----------------------------------------------------------------------

$current_time = Time::HiRes::gettimeofday();
$time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
$last_time = $current_time;
print STDOUT $time_msg;
print $time_msg;

#######################################################################
### Handle FASTA sequences --------------------------------------------
#######################################################################

$step_name = "Handle FASTA sequences";

$time_msg = getStepTimebBeginMsg($exec_id, $step_name);
print STDOUT $time_msg;
print $time_msg;

# -----------------------------------------------------------------------

my $path_03_map_host_sam = "$step3/mapped_host.v1.sam";
my $path_03_map_host_stats = "$step3/mapping_host.stats";

my $path_04_unmap_vector_reads_fa = "$step4/unmappedVectorReads.fasta";
my $path_04_unmap_vector_bacters_fa = "$step4/unmappedVectorBacters.fasta";
my $path_04_unmap_trim_filter_fa = "$step4/unmapped_trimmed_filtered.fasta";
my $path_04_unmap_trim_filter_20_23_fa = "$step4/unmapped_trimmed_filtered.20-23.fasta";
my $path_04_unmap_trim_filter_24_30_fa = "$step4/unmapped_trimmed_filtered.24-30.fasta";
my $path_04_reads_map_bacteria_log = "$step4/reads_mapped_to_bacteria.log";

# 
# REVIEW: 2023-03-01 - Shall we think of better names?
# 

my $mappedbac;
my $nReadsUnmapHostBac;
# my $nReadsUnmapHost;

print "# Loading FASTA file ... \n";

if (not defined($nohostfilter)) {

    if (not defined($fastq)) {

        my $cmd = "cp $fasta $path_02_trim_filtered_gt15_fa";

        print "[COPING $fasta TO $path_02_trim_filtered_gt15_fa]\n";
        `$cmd`;
        
        print "\n[STEP 03]\n\t $cmd\n";
    }

# } else {

#     # 
#     # REVIEW: 2023-03-01 - Check this step numbering
#     # TODO: 2023-03-01 - Test it
#     # 

#     # Mapping Host - unfiltered reads against bacters reference
#     print "[MAPPING HOST-UNFILTERED READS AGAINST BACTERIAL GENOMES]... \n";

#     my $exec5_1 = "bowtie -f -S -v 1 --un $path_04_unmap_vector_bacters_fa -k 1 -p $process --large-index ".REF_BACTERIA_GENOMES." $fasta > /dev/null 2>> $path_04_reads_map_bacteria_log";
    
#     print "\n[STEP 05.1]\n\t $exec5_1\n";
#     `$exec5_1`;

#     $nReadsUnmapHostBac = `grep -c '>' $path_04_unmap_vector_bacters_fa`;
#     chomp($nReadsUnmapHostBac);

#     # Mapped reads Bacterial genomes
#     # print metrics "# Pre processed reads\t".$nReadsUnmapHostBac."\n"; # TODO: 2023-03-01 - Check this 'metrics' log
#     print "# Pre processed reads\t $nReadsUnmapHostBac \n"; # REVIEW: 2023-03-01 - Does this message really make sense?
    
#     # $mappedbac = $nReadsUnmapHost - $nReadsUnmapHostBac; # REVIEW: 2023-03-01 - It doesn't look like it works
#     # print metrics "#reads mapped bacter\t".$mappedbac."\n"; # TODO: 2023-03-01 - Check this 'metrics' log
#     # print "#reads mapped bacter\t".$mappedbac."\n";
    
#     print "\n  PRE-PROCESSING FINISHED \n"; # REVIEW: 2023-03-01 - Does this message really make sense?
}

if (not defined($nohostfilter)) {

    print "[MAPPING SEQUENCE AGAINST VECTOR]\n";
    my $exec3 = "bowtie $large_index -f -S -k 1 -p $process -v 1 --un $path_04_unmap_vector_reads_fa $hostgenome $path_02_trim_filtered_gt15_fa | awk -F'\\t' '{if( \$2 != 4) print \$0}' > $path_03_map_host_sam  2>$path_03_map_host_stats  ";
    
    print "\n[STEP 03]\n\t $exec3\n";
    `$exec3`;

    # #count total reads
    my $nReads = `grep -c '>' $path_02_trim_filtered_gt15_fa`;
    chomp($nReads);

    # print metrics "#total reads\t".$nReads. # REVIEW: 2023-03-06 - What should we do with these 'special' logs?
    # print interest "#total reads\t".$nReads. # REVIEW: 2023-03-06 - What should we do with these 'special' logs?
    print "# Total reads\t".$nReads."\n";

    # 
    # TODO: 2023-06-06 - Convert .sam into .bam
    # 

    print "[PLOT GERAL DISTRIBUTION READS MAPPED HOST ]\n";
    my $exec3_1 = "perl $path_plot_dist_per_base_by_reads -sam $path_03_map_host_sam  -s $si -e $se -p $step3/mapped_host.v1.$si.$se -norm $nReads --plot";
    
    print "\n[STEP 03]\n\t $exec3_1\n";
    `$exec3_1`;

    print "[PLOT GERAL DISTRIBUTION READS MAPPED HOST - 15-35nt ]\n";
    my $exec3_11 = "perl $path_plot_dist_per_base_by_reads -sam $path_03_map_host_sam  -s 15 -e 35 -p $step3/mapped_host.v1 -norm $nReads --plot";
    
    print "\n[STEP 03]\n\t $exec3_11\n";
    `$exec3_11`;

    my $nReadsUnmapHost = `grep -c '>' $path_04_unmap_vector_reads_fa`;
    chomp($nReadsUnmapHost);
    my $mapped = $nReads - $nReadsUnmapHost;

    # Mapped reads HOST
    # print interest "# Reads mapped host\t".$mapped. # REVIEW: 2023-03-06 - What should we do with these 'special' logs?
    print "# Reads mapped host\t".$mapped."\n";
    
    # Unmapped reads HOST
    # print interest "# Reads unmapped host\t".$nReadsUnmapHost. # REVIEW: 2023-03-06 - What should we do with these 'special' logs?
    print "# Reads unmapped host\t".$nReadsUnmapHost."\n";

    # Deleting sam file mapped reads on host genome
    # `rm -rf $path_03_map_host_sam`;

    # Mapping Host - filtered reads against bacters reference
    print "[MAPPING HOST-FILTERED READS AGAINST BACTERIAL GENOMES]... \n";
    my $exec5_1 = "bowtie -f -S -v 1 --un $path_04_unmap_vector_bacters_fa -k 1 -p $process --large-index ".REF_BACTERIA_GENOMES." $path_04_unmap_vector_reads_fa > /dev/null 2>>$path_warns ";
    
    print "\n[STEP 05.1]\n\t $exec5_1\n";
    `$exec5_1`;

    $nReadsUnmapHostBac = `grep -c '>' $path_04_unmap_vector_bacters_fa`;
    chomp($nReadsUnmapHostBac);
    $mappedbac = $nReadsUnmapHost - $nReadsUnmapHostBac;

    # Mapped reads Bacterial genomes
    # print metrics "# Reads mapped bacter\t".$mappedbac. # REVIEW: 2023-03-06 - What should we do with these 'special' logs?
    print "# Reads mapped bacter\t".$mappedbac."\n";
    
    # Pre processed reads
    # print metrics "# Preprocessed reads\t".$nReadsUnmapHostBac. # REVIEW: 2023-03-06 - What should we do with these 'special' logs?
    print "# Preprocessed reads\t".$nReadsUnmapHostBac."\n";
    
    print "\n PRE-PROCESSING FINISHED \n";
}

# -----------------------------------------------------------------------

$current_time = Time::HiRes::gettimeofday();
$time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
$last_time = $current_time;
print STDOUT $time_msg;
print $time_msg;

#######################################################################
### Select filtered sequences by size ---------------------------------
#######################################################################

$step_name = "Select filtered sequences by size";

$time_msg = getStepTimebBeginMsg($exec_id, $step_name);
print STDOUT $time_msg;
print $time_msg;

# -----------------------------------------------------------------------

# By default we've being using 18 ~ 30 nt as arguments

# 
# TODO: 2023-05-11 - Use 15 ~ 35nt as default
# 

print "[FILTER UNMAPPED SEQUENCES BY SIZE (variable size $si to $se)]\n";

my $exec5 = "python3 $path_filter_fasta_by_size $path_04_unmap_vector_bacters_fa $si $se $path_04_unmap_trim_filter_fa -t F ";

print "\n[STEP 05]\n\t $exec5\n";
`$exec5`;

print "[FILTER UNMAPPED SEQUENCES BY SIZE (20-23NT)]\n";
my $exec5_1 = "python3 $path_filter_fasta_by_size $path_04_unmap_vector_bacters_fa 20 23 $path_04_unmap_trim_filter_20_23_fa";
print "\n[STEP 05.1]\n\t $exec5_1\n";
`$exec5_1`;

print "[FILTER UNMAPPED SEQUENCES BY SIZE (24-30NT)]\n";
my $exec5_2 = "python3 $path_filter_fasta_by_size $path_04_unmap_vector_bacters_fa 24 30 $path_04_unmap_trim_filter_24_30_fa";
print "\n[STEP 05.2]\n\t $exec5_2\n";
`$exec5_2`;

$current_time = Time::HiRes::gettimeofday();
$time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
$last_time = $current_time;
print STDOUT $time_msg;
print $time_msg;

#######################################################################
### Run Velvet optmiser (automatically defined hash) ------------------
#######################################################################

$step_name = "Run Velvet optmiser (automatically defined hash)";

$time_msg = getStepTimebBeginMsg($exec_id, $step_name);
print STDOUT $time_msg;
print $time_msg;

# -----------------------------------------------------------------------

my $path_05_1_opt_contigs_final_fa = "$step5_1_opt/contigs.final.fasta";

my $path_05_1_opt_run1_dir = "$step5_1_opt/run1";
my $path_05_1_opt_run1_contigs_fa = "$path_05_1_opt_run1_dir/contigs.fa"; # $step5_1_opt/run1/contigs.fa

my $path_05_1_opt_run2_dir = "$step5_1_opt/run2";
my $path_05_1_opt_run2_scaffolds_fa = "$path_05_1_opt_run2_dir/scaffolds.fasta"; # $step5_1_opt/run2/scaffolds.fasta

print "\n#[RUNNING VELVET OPTIMIZER]\n";
print "\t#Running step 6 [ Assemble unmapped 21 nt - velvetOptimser.pl ]\n";

my $exec6_1 = "velvetoptimiser --d $path_05_1_opt_run1_dir --t $process --s 13 --e 19 --f '-short -fasta $path_04_unmap_trim_filter_fa' --a $process 2>>$path_warns";

print "\n[STEP 06.1]\n\t $exec6_1\n";
`$exec6_1`;

print "\t#Running step 6_4 [ SPADES ] \n";
my $exec6_4 = "spades -s $path_04_unmap_trim_filter_fa --careful --only-assembler -t $process -k 13,15,17,19 -o $path_05_1_opt_run2_dir";

print "\n[STEP 06.4]\n\t $exec6_4\n";
`$exec6_4`;

print "\t#Running step 6_5 [ merge assemblies - mergeContigs.pl ] \n";

if (not -e $path_05_1_opt_run1_dir) {
    `mkdir $path_05_1_opt_run1_dir`;
}
if (not -e $path_05_1_opt_run1_contigs_fa) {
    `touch $path_05_1_opt_run1_contigs_fa`;
}
if (not -e $path_05_1_opt_run2_scaffolds_fa) {
    `touch $path_05_1_opt_run2_scaffolds_fa`;
}

my $exec6_5 = "perl $path_merge_contigs -contig1 $path_05_1_opt_run1_contigs_fa -contig2 $path_05_1_opt_run2_scaffolds_fa -output $path_05_1_opt_contigs_final_fa ";

if (not -e $path_05_1_opt_contigs_final_fa) {
    `touch $path_05_1_opt_contigs_final_fa`;
}

print "\n[STEP 06.5]\n\t $exec6_5\n";
`$exec6_5`;

# -----------------------------------------------------------------------

$current_time = Time::HiRes::gettimeofday();
$time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
$last_time = $current_time;

print STDOUT $time_msg;
print $time_msg;

#######################################################################
### Running velvet (fixed hash) ---------------------------------------
#######################################################################

$step_name = "Running velvet (fixed hash)";

$time_msg = getStepTimebBeginMsg($exec_id, $step_name);
print STDOUT $time_msg;
print $time_msg;

# -----------------------------------------------------------------------

my $path_05_2_fix_contigs_final_fa = "$step5_2_fix/contigs.final.fasta";

my $path_05_2_fix_run1_dir = "$step5_2_fix/run1";
my $path_05_2_fix_run1_contigs_fa = "$path_05_2_fix_run1_dir/contigs.fa"; # $step5_2_fix/run1/contigs.fa

my $path_05_2_fix_run2_dir = "$step5_2_fix/run2";
my $path_05_2_fix_run2_scaffolds_fa = "$path_05_2_fix_run2_dir/scaffolds.fasta"; # $step5_2_fix/run2/scaffolds.fasta

print "\n[RUNNING DEFAULT VELVET]\n";
print "\t#Running step 6 [ Assemble unmapped 21 nt - velvet hash $hash ]\n";

my $exec6 = "velveth $path_05_2_fix_run1_dir $hash -fasta -short $path_04_unmap_trim_filter_fa 2>>$path_warns";

print "\n[STEP 06]\n\t $exec6\n";
`$exec6`;

`velvetg $path_05_2_fix_run1_dir -exp_cov auto -cov_cutoff auto 2>$path_warns`;

`mkdir $path_05_2_fix_run2_dir`;

print "\t#Running SPADES fixed hash  [ SPADES ] \n";
my $exec6_2 = "spades -s $path_04_unmap_trim_filter_fa --careful --only-assembler -t $process  -k $hash -o $path_05_2_fix_run2_dir";

print "\n[STEP 06.2]\n\t $exec6_2\n";
`$exec6_2`;

print "\t#Running step 6_5 [ merge assemblies - mergeContigs.pl ] \n";

if (not -e $path_05_2_fix_run1_dir) {
    `mkdir $path_05_2_fix_run1_dir`;
}
if (not -e $path_05_2_fix_run1_contigs_fa) {
    `touch $path_05_2_fix_run1_contigs_fa`;
}
if (not -e $path_05_2_fix_run2_scaffolds_fa) {
    `touch $path_05_2_fix_run2_scaffolds_fa`;
}

$exec6_5 = "perl $path_merge_contigs -contig1 $path_05_2_fix_run1_contigs_fa -contig2 $path_05_2_fix_run2_scaffolds_fa -output $path_05_2_fix_contigs_final_fa";

if (not -e $path_05_2_fix_contigs_final_fa) {
    `touch $path_05_2_fix_contigs_final_fa`;
}

print "\n[STEP 06.5]\n\t $exec6_5\n";
`$exec6_5`;

# -----------------------------------------------------------------------

$current_time = Time::HiRes::gettimeofday();
$time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
$last_time = $current_time;

print STDOUT $time_msg;
print $time_msg;

#######################################################################
### Running velvet optmiser (FIXED hash) ------------------------------
#######################################################################

$step_name = "Running velvet optmiser (FIXED hash)";

$time_msg = getStepTimebBeginMsg($exec_id, $step_name);
print STDOUT $time_msg;
print $time_msg;

# -----------------------------------------------------------------------

my $path_05_3_opt_fix_contigs_final_fa = "$step5_3_opt_fix/contigs.final.fasta";

my $path_05_3_opt_fix_run1_dir = "$step5_3_opt_fix/run1";
my $path_05_3_opt_fix_run1_contigs_fa = "$path_05_3_opt_fix_run1_dir/contigs.fa"; # $step5_3_opt_fix/run1/contigs.fa

my $path_05_3_opt_fix_run2_dir = "$step5_3_opt_fix/run2";
my $path_05_3_opt_fix_run2_scaffolds_fa = "$path_05_3_opt_fix_run2_dir/scaffolds.fasta"; # $step5_3_opt_fix/run2/scaffolds.fasta

print "\n[VELVET OPTIMISER HASH ONLY 15]\n";
print "\t#Running step 6_6 [ Assemble unmapped 21 nt - velvetOptimser.pl ]\n";
my $exec6_6 = "velvetoptimiser --d $path_05_3_opt_fix_run1_dir --t $process --s $hash --e $hash --f '-short -fasta $path_04_unmap_trim_filter_fa' --a 2>>$path_warns";

print "\n[STEP 06.1]\n\t $exec6_6\n";
`$exec6_6`;

`mkdir $path_05_3_opt_fix_run2_dir`;
print "\t#Running SPADES fixed hash  [ SPADES ] \n";
my $exec6_6_2 = "spades -s $path_04_unmap_trim_filter_fa --careful --only-assembler -t $process  -k 15 -o $path_05_3_opt_fix_run2_dir ";

print "\n[STEP 06.2]\n\t $exec6_2\n";
`$exec6_6_2`;

print "\t#Running step 6_9 [ merge assemblies - mergeContigs.pl ] \n";

if (not -e $path_05_3_opt_fix_run1_dir) {
    `mkdir $path_05_3_opt_fix_run1_dir`;
}
if (not -e $path_05_3_opt_fix_run1_contigs_fa) {
    `touch $path_05_3_opt_fix_run1_contigs_fa`;
}
if (not -e $path_05_3_opt_fix_run2_scaffolds_fa) {
    `touch $path_05_3_opt_fix_run2_scaffolds_fa`;
}

my $exec6_9 = "perl $path_merge_contigs -contig1 $path_05_3_opt_fix_run1_contigs_fa -contig2 $path_05_3_opt_fix_run2_scaffolds_fa -output $path_05_3_opt_fix_contigs_final_fa";

if (not -e $path_05_3_opt_fix_contigs_final_fa) {
    `touch $path_05_3_opt_fix_contigs_final_fa`;
}

print "\n[STEP 06.5]\n\t $exec6_5\n";
`$exec6_9`;

# -----------------------------------------------------------------------

$current_time = Time::HiRes::gettimeofday();
$time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
$last_time = $current_time;

print STDOUT $time_msg;
print $time_msg;

#######################################################################
### Running velvet optmiser (FIXED hash) 20-23 ------------------------
#######################################################################

$step_name = "Running velvet optmiser (FIXED hash) 20-23";

$time_msg = getStepTimebBeginMsg($exec_id, $step_name);
print STDOUT $time_msg;
print $time_msg;

# -----------------------------------------------------------------------

my $path_05_4_opt_20_23_contigs_final_fa = "$step5_4_opt_20to23/contigs.final.fasta";

my $path_05_4_opt_20_23_run1_dir = "$step5_4_opt_20to23/run1";
my $path_05_4_opt_20_23_run1_contigs_fa = "$path_05_4_opt_20_23_run1_dir/contigs.fa"; # $step5_4_opt_20to23/run1/contigs.fa

my $path_05_4_opt_20_23_run2_dir = "$step5_4_opt_20to23/run2";
my $path_05_4_opt_20_23_run2_scaffolds_fa = "$path_05_4_opt_20_23_run2_dir/scaffolds.fasta"; # $step5_4_opt_20to23/run2/scaffolds.fasta

print "\n[VELVET OPTIMISER HASH ONLY 15 - 20-23nt]\n";
print "\t#Running step 6_10 [ Assemble unmapped 20-23nt nt - velvetOptimser.pl ]\n";
my $exec6_10 = "velvetoptimiser --d $path_05_4_opt_20_23_run1_dir --t $process --s $hash --e $hash --f '-short -fasta $path_04_unmap_trim_filter_20_23_fa' --a 2>>$path_warns";

print "\n[STEP 06.1]\n\t $exec6_10\n";
`$exec6_10`;

`mkdir $path_05_4_opt_20_23_run2_dir`;
print "\t#Running SPADES fixed hash  [ SPADES ] \n";
my $exec6_10_2 = "spades -s $path_04_unmap_trim_filter_20_23_fa  --careful --only-assembler -t $process  -k $hash -o $path_05_4_opt_20_23_run2_dir";

print "\n[STEP 06.10.2]\n\t $exec6_2\n";
`$exec6_10_2`;

print "\t#Running step 6_13 [ merge assemblies - mergeContigs.pl ] \n";

if (not -e $path_05_4_opt_20_23_run1_dir) {
    `mkdir $path_05_4_opt_20_23_run1_dir`;
}
if (not -e $path_05_4_opt_20_23_run1_contigs_fa) {
    `touch $path_05_4_opt_20_23_run1_contigs_fa`;
}
if (not -e $path_05_4_opt_20_23_run2_scaffolds_fa) {
    `touch $path_05_4_opt_20_23_run2_scaffolds_fa`;
}

my $exec6_13 = "perl $path_merge_contigs -contig1 $path_05_4_opt_20_23_run1_contigs_fa -contig2 $path_05_4_opt_20_23_run2_scaffolds_fa -output $path_05_4_opt_20_23_contigs_final_fa ";

if (not -e $path_05_4_opt_20_23_contigs_final_fa) {
    `touch $path_05_4_opt_20_23_contigs_final_fa`;
}

print "\n[STEP 06.13]\n\t $exec6_13\n";
`$exec6_13`;

# -----------------------------------------------------------------------

$current_time = Time::HiRes::gettimeofday();
$time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
$last_time = $current_time;

print STDOUT $time_msg;
print $time_msg;

# #######################################################################
# ### Running velvet optmiser (hash 17) 24-30 ---------------------------
# #######################################################################

# $step_name = "Running velvet optmiser (hash 17) 24-30";

# $time_msg = getStepTimebBeginMsg($exec_id, $step_name);
# print STDOUT $time_msg;
# print $time_msg;

# # -----------------------------------------------------------------------

my $path_05_5_cap3_final_24_30_fa = "$step5_5_opt_24to30/contigs.final.fasta";
my $path_05_5_cap3_gt200_fa = "$step5_6_cap3/contigs_merged.final.gt200.fasta";
my $path_05_5_cap3_gt50_fa = "$step5_6_cap3/contigs_merged.final.gt50.fasta";

#
# TODO: 2023-05-31 - Test this condition
# 

# if (defined($deg)) {
    
#     print "\n[VELVET OPTIMISER - 24-30nt]\n";
#     print "\t#Running step 6_10 [ Assemble unmapped 24-30nt nt - velvetOptimser.pl ]\n";
    
#     my $exec62_10 = "velvetoptimiser --d $step5_5_opt_24to30/run1 --t $process --s 15 --e 17 --f '-short -fasta $path_04_unmap_trim_filter_24_30_fa' --a 2>>$path_warns";
    
#     print "\nSTEP62_10\n\t $exec62_10\n";
#     `$exec62_10`;

#     `mkdir $step5_5_opt_24to30/run2 `;

#     print "\t#Running SPADES fixed hash  [ SPADES ] \n";
#     my $exec6_10_3 = "spades -s $path_04_unmap_trim_filter_24_30_fa --careful --only-assembler -t $process  -k 15,17 -o $step5_5_opt_24to30/run2 ";
    
#     print "\n[STEP 06.10_3\n\t $exec6_2\n";
#     `$exec6_10_3`;

#     print "\t#Running step 6_13 [ merge assemblies - mergeContigs.pl ] \n";
#     my $exec62_13 = "perl $path_merge_contigs -contig1 $step5_5_opt_24to30/run1/contigs.fa -contig2 $step5_5_opt_24to30/run2/scaffolds.fasta -output $path_05_5_cap3_final_24_30_fa ";
#     print "\nSTEP62_13\n\t $exec62_13\n";
#     `$exec62_13`;
# }

# # -----------------------------------------------------------------------

# $current_time = Time::HiRes::gettimeofday();
# $time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
# $last_time = $current_time;

# print STDOUT $time_msg;
# print $time_msg;

#######################################################################
### Merging assemblies ------------------------------------------------
#######################################################################

$step_name = "Merging assemblies";

$time_msg = getStepTimebBeginMsg($exec_id, $step_name);
print STDOUT $time_msg;
print $time_msg;

# -----------------------------------------------------------------------

my $path_05_6_cap3_all_fa = "$step5_6_cap3/all_contigs.fasta";

if (not defined($deg)) {
    `touch $path_05_5_cap3_final_24_30_fa`;
}

print "\n[MERGING CONTIGS AND RUNNING CAP3]\n";
print "\t#Running STEP [CAT] Concatenating contigs...\n";
my $exec_cat = "cat $path_05_4_opt_20_23_contigs_final_fa $path_05_3_opt_fix_contigs_final_fa  $path_05_2_fix_contigs_final_fa $path_05_1_opt_contigs_final_fa $path_05_5_cap3_final_24_30_fa > $path_05_6_cap3_all_fa";

print "\n[STEP 06.CAT] \n\t $exec_cat\n";
`$exec_cat`;

print "\t#Running step CAP3 [ assembly contigs from different assemblies ] \n";
my $exec_cap3 = "cap3 $path_05_6_cap3_all_fa  > $step5_6_cap3/log.cap3";
print "\nSTEP CAP3\n\t $exec_cap3\n";
`$exec_cap3`;

print "\t#Running [ Concatenning contigs and singlets from CAP3]\n";
my $exec_cap3_1 = "cat $path_05_6_cap3_all_fa.cap.contigs $path_05_6_cap3_all_fa.cap.singlets > $step5_6_cap3/contigs_merged.final.fasta";

print "\n[STEP 06.CAT]\n\t $exec_cap3_1\n";
`$exec_cap3_1`;

print "\t#Running step 6_7 [ selecting contigs larger than n50 - calcN50.pl ] \n";
my $step6_7 = "perl $path_fix_cap3_contigs -i $step5_6_cap3/contigs_merged.final.fasta -s 50  -p $step5_6_cap3/contigs_merged.final";

print "\n[STEP 06.7]\n\t $step6_7\n";
`$step6_7`;

my $countAssembledContigs = `grep -c '>' $path_05_5_cap3_gt50_fa`;
chomp($countAssembledContigs);

# print metrics "# Total assembled contigs\t" . $countAssembledContigs. "\n"; # Assembled Contigs
# print interest "# Total assembled contigs\t" . $countAssembledContigs . "\n"; # Assembled Contigs
print "# Total assembled contigs\t" . $countAssembledContigs. "\n"; # Assembled Contigs

# 
# TODO: 2023-08-31 - Differentiate variables for counts of all contigs or contigs >= 200 
# 
my $__DONT_USE_it_yet_n_contigs_gt200 = 0;

if ($countAssembledContigs) {
    print "[FILTER CONTIGS gt 200 nt]\n";
    my $exec_FC2 = "python3 $path_filter_fasta_by_size $path_05_5_cap3_gt50_fa 200 1000000 $path_05_5_cap3_gt200_fa";

    print "\n[STEP 05.2]\n\t $exec_FC2\n";
    `$exec_FC2`;

    # 
    # TODO: 2023-08-31 - Differentiate variables for counts of all contigs or contigs >= 200 
    # 
    # $countAssembledContigs = `grep -c '>' $path_05_5_cap3_gt200_fa`;
    # chomp($countAssembledContigs);
    
    $__DONT_USE_it_yet_n_contigs_gt200 = `grep -c '>' $path_05_5_cap3_gt200_fa`;
    chomp($__DONT_USE_it_yet_n_contigs_gt200);
    print "# Contigs gt200\t".$__DONT_USE_it_yet_n_contigs_gt200. "\n";
}

# -----------------------------------------------------------------------

$current_time = Time::HiRes::gettimeofday();
$time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
$last_time = $current_time;

print STDOUT $time_msg;
print $time_msg;

# -----------------------------------------------------------------------

if (!$__DONT_USE_it_yet_n_contigs_gt200) {
    
    my $err_msg = $countAssembledContigs
        ? "No contigs >= 200nt!"
        : "No contigs assembled!";

    my $final_msg = "\n\n -- $err_msg --\n -- This means ending execution with NO ERROR! -- \n\n";
    finishSuccesfully($final_msg);
}

$countAssembledContigs = $__DONT_USE_it_yet_n_contigs_gt200;

#######################################################################
### Blastn ------------------------------------------------------------
#######################################################################

$step_name = "Blastn";

$time_msg = getStepTimebBeginMsg($exec_id, $step_name);
print STDOUT $time_msg;
print $time_msg;

# -----------------------------------------------------------------------

my $path_06_blastn_no_hit_1e5_fa = "$step6/seqNoHit.blastN.1e5.fasta";
my $path_06_blastn_merge_gt200_1e5 = "$step6/contigs_merged.final.gt200.1e5.blastn";

my $path_07_bN_analyse_blastn_prefix = "$step7/contigs.bN.blastn.analyze";
my $path_07_bN_analize_viral_fa = "$path_07_bN_analyse_blastn_prefix.virus.contigs.fasta"; # $step7/contigs.bN.blastn.analyze.virus.contigs.fasta"
my $path_07_bN_analize_viral_header_fa = "$path_07_bN_analyse_blastn_prefix.virus.contigs.header.fasta"; # $step7/contigs.bN.blastn.analyze.virus.contigs.header.fasta"

my $path_07_bN_analyze_prefix = "$step7/contigs.bN.analyze";
my $path_07_bN_analize_contigs_fa = "$path_07_bN_analyze_prefix..contigs.fasta"; # "$step7/contigs.bN.analyze..contigs.fasta"
my $path_07_bN_analize_non_viral_fa = "$path_07_bN_analyze_prefix.nonviral.contigs.fasta"; # "$step7/contigs.bN.analyze.nonviral.contigs.fasta";
my $path_07_bN_analize_non_viral_header_fa = "$path_07_bN_analyze_prefix.nonviral.contigs.header.fasta"; # "$step7/contigs.bN.analyze.nonviral.contigs.header.fasta";

my $path_07_blastn_analyse = "$step7/contigs.blastN.analyze";
my $path_07_blastn_analize_virus = "$step7/contigs.blastN.virus.analyze";
my $path_07_blastn_1e5_report = "$step7/contigs.blastn.1e5.report";
my $path_07_blastn_virus_fa = "$step7/contigs.virus.blastN.formatted.fasta";
my $path_07_blastn_virus_header_fa = "$step7/contigs.virus.blastN.formatted.header.fasta";

my $path_07_dmnd_log = "$step7/diamond.log";
my $path_07_dmnd_hits_fa = "$step7/diamond_blastx_Hits.fasta";
my $path_07_dmnd_out = "$step7/diamond_blastx.out";

my $path_07_dmnd_viral_header_fa = "$step7/diamond_blastx_Viral.header.fasta";
my $path_07_dmnd_non_viral_header_fa = "$step7/diamond_blastx_NonViral.header.fasta";

my $path_07_dmnd_no_hits_prefix = "$step7/diamond_blastx_NoHits";
my $path_07_dmnd_no_hits_fa = "$path_07_dmnd_no_hits_prefix.fasta";
my $path_07_dmnd_no_hits_linear_fa = "${path_07_dmnd_no_hits_prefix}_linear.fasta";
my $path_07_dmnd_no_hits_header_fa = "${path_07_dmnd_no_hits_prefix}_linear.header.fasta";
my $path_07_dmnd_no_hits_log = "${path_07_dmnd_no_hits_prefix}_bowtie.log";
my $path_07_dmnd_no_hits_sam = "$path_07_dmnd_no_hits_prefix.sam";
my $path_07_dmnd_no_hits_sam_mapped = "$path_07_dmnd_no_hits_prefix.mapped.sam";
my $path_07_dmnd_no_hits_sam_sort = "$path_07_dmnd_no_hits_prefix.mapped.sort.sam";

my $path_07_all_viral_prefix = "$step7/all_viral_hits";
my $path_07_all_viral_fa = "$path_07_all_viral_prefix.fasta";
my $path_07_all_viral_log = "${path_07_all_viral_prefix}_bowtie.log";
my $path_07_all_viral_sam_mapped = "$path_07_all_viral_prefix.mapped.sam";
my $path_07_all_viral_sam_sort = "$path_07_all_viral_prefix.mapped.sort.sam";

my $path_07_all_non_viral_prefix = "$step7/all_non_viral_hits";
my $path_07_all_non_viral_fa = "$path_07_all_non_viral_prefix.fasta";
my $path_07_all_non_viral_log = "${path_07_all_non_viral_prefix}_bowtie.log";
my $path_07_all_non_viral_sam_mapped = "$path_07_all_non_viral_prefix.mapped.sam";
my $path_07_all_non_viral_sam_sort = "$path_07_all_non_viral_prefix.mapped.sort.sam";

my $path_07_all_viral_sam = "$path_07_all_viral_prefix.sam";
my $path_07_all_non_viral_sam = "$path_07_all_non_viral_prefix.sam";

my $path_07_aux_fa = "$step7/aux.fasta";
my $path_07_aux_non_viral = "$step7/aux_nonviral";

print "\n[BlastN contigs gt 200]\n";
print "\t#Running step 10_111 [ Blast against NT - blast+ blastn ]\n";
my $exec10_111 = "blastn -query $path_05_5_cap3_gt200_fa -db ".REF_BLAST_DB_NT."/nt -num_descriptions 5 -num_alignments 5 -evalue 1e-5 -out $path_06_blastn_merge_gt200_1e5  -num_threads $process";

print "\nSTEP10_111\n\t $exec10_111\n";
`$exec10_111`;

print "\t#Running filterblast...\n";
my $exec10_112 = "perl $path_filter_blast -b $path_06_blastn_merge_gt200_1e5 -evalue 1e-5 --best --desc > $path_07_blastn_1e5_report";

print "\nSTEP10_112\n\t $exec10_112\n";
`$exec10_112`;

print "\n Extracting contigs all Hits blastn 1e-5... \n";
`perl $path_analyse_contigs_blastn -i $path_07_blastn_1e5_report  -f $path_05_5_cap3_gt200_fa -q "" -p  $path_07_bN_analyze_prefix > $path_07_blastn_analyse`;

print "\n Extracting contigs viral blastn 1e-5...\n";
`perl $path_analyse_contigs_blastn -i $path_07_blastn_1e5_report  -f $path_05_5_cap3_gt200_fa -q "virus" -p  $path_07_bN_analyse_blastn_prefix > $path_07_blastn_analize_virus`;

print "\n Extracting contigs nonviral blastn 1e-5...\n";
`grep -v -i "virus" $path_07_bN_analize_contigs_fa | grep '>' | cut -f1 -d " " >  $path_07_aux_non_viral`;

my $cmd_fa_format = "fasta_formatter -i $path_07_bN_analize_contigs_fa > $path_07_aux_fa";
print "\n Running fasta_formatter: \n\t $cmd_fa_format";
`$cmd_fa_format`;

`while read p; do grep -A1 \${p} $path_07_aux_fa >> $path_07_bN_analize_non_viral_fa;done < $path_07_aux_non_viral`;
`rm -f $path_07_aux_fa`;
`rm -f $path_07_aux_non_viral`;

if (not -e $path_07_bN_analize_non_viral_fa) {
    `touch $path_07_bN_analize_non_viral_fa`;
}

my $n_blastn_hits = `grep -c '>' $path_07_bN_analize_contigs_fa`;
chomp($n_blastn_hits);
$n_blastn_hits = int($n_blastn_hits);
print "\n# Number of contigs (blastN) [hits]\t".$n_blastn_hits."\n";

my $n_blastn_hits_virus = `grep -c '>' $path_07_bN_analize_viral_fa`;
chomp($n_blastn_hits_virus);
$n_blastn_hits_virus = int($n_blastn_hits_virus);
print "\n# Number of contigs (blastN) [viral]\t".$n_blastn_hits_virus."\n";

my $n_blastn_hits_non_viral = `grep -c '>' $path_07_bN_analize_non_viral_fa`;
chomp($n_blastn_hits_non_viral);
$n_blastn_hits_non_viral = int($n_blastn_hits_non_viral);
print "\n# Number of contigs (blastN) [non viral]\t".$n_blastn_hits_non_viral."\n";

print "\n[Extracting contigs no hit blastn 1e-5]\n";
my $exec10_113 = "perl $path_extract_seqs_no_hit_blast -seq $path_05_5_cap3_gt200_fa -blast $path_07_blastn_1e5_report -out $path_06_blastn_no_hit_1e5_fa";

print "\nSTEP10_113\n\t $exec10_113\n";
`$exec10_113`;

my $n_blastn_no_hits = `grep -c '>' $path_06_blastn_no_hit_1e5_fa`;
chomp($n_blastn_no_hits);
$n_blastn_no_hits = int($n_blastn_no_hits);
print "# Number of contigs (blastN) [no hits]\t".$n_blastn_no_hits."\n";

`cat $path_07_bN_analize_viral_fa | perl -pi -e 's/>(\\S+) (\\S+) (\\S+) (\\S+).+/>blastN_\$1_\$2_\$3_\$4/g' > $path_07_blastn_virus_fa`;

# -----------------------------------------------------------------------

$current_time = Time::HiRes::gettimeofday();
$time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
$last_time = $current_time;

print STDOUT $time_msg;
print $time_msg;

#######################################################################
### DIAMOND (Blastx) --------------------------------------------------
#######################################################################

$step_name = "DIAMOND (Blastx)";

$time_msg = getStepTimebBeginMsg($exec_id, $step_name);
print STDOUT $time_msg;
print $time_msg;

# -----------------------------------------------------------------------

if ($n_blastn_no_hits) {

    print "\n[Diamond (BlastX) contigs gt 200]\n";
    print "\t# Running step 9 [ Diamond-Blast against NR ]\n";

    my $exec9 = "diamond blastx -q $path_06_blastn_no_hit_1e5_fa -d ".REF_DIAMOND_NR." -k 5 -p $process -e 0.001 -f 0 -c 1 -b 20 --very-sensitive -o $path_07_dmnd_out --un $path_07_dmnd_no_hits_fa --unfmt fasta --al $path_07_dmnd_hits_fa --alfmt fasta 2>  $path_07_dmnd_log";

    print "\nSTEP9\n\t $exec9\n";
    `$exec9`;

    print "\t# Filtering Diamond results... ]\n";   
    my $exec9_11 = "$path_filter_diamond -f $path_07_dmnd_hits_fa -o $path_07_dmnd_out -d $step7";

    print "\nSTEP9_11\n\t $exec9_11\n";
    `$exec9_11`;

    # Replace '\t' characters with actual tabs
    `sed -i 's/\\\\t/\\t/g' $path_07_dmnd_no_hits_fa`;

    # Make a 'linear' version of 'no hits' fasta (join all pieces for each sequence)
    `fasta_formatter -i $path_07_dmnd_no_hits_fa -o $path_07_dmnd_no_hits_linear_fa`;
    # `rm $path_07_dmnd_no_hits_fa`;
}

# Add prefix to all contig names
`for file in $step7/*.fasta; do
    if [ -f "\$file" ]; then
        filename=\$(basename "\$file")
        filename_without_ext="\${filename%.*}"
        sed 's/^>/>${lib_prefix}_/' $step7/\$filename > $step7/\${filename_without_ext}.header.fasta
    fi
done
`;

# Compute number of contigs (diamond) [hits]
if (not -e $path_07_dmnd_hits_fa) {
    `touch $path_07_dmnd_hits_fa`;
}

my $n_dmnd_hits = `grep -c '>' $path_07_dmnd_hits_fa`;
chomp($n_dmnd_hits);
$n_dmnd_hits = int($n_dmnd_hits);

print "# Number of contigs (diamond) [hits]\t".$n_dmnd_hits."\n";

# Compute number of contigs (diamond) [viral]
if (not -e $path_07_dmnd_viral_header_fa) {
    `touch $path_07_dmnd_viral_header_fa`;
}

my $n_dmnd_hits_viral = `grep -c '>' $path_07_dmnd_viral_header_fa`;
chomp($n_dmnd_hits_viral);
$n_dmnd_hits_viral = int($n_dmnd_hits_viral);

print "# Number of contigs (diamond) [viral]\t".$n_dmnd_hits_viral."\n";

# Compute number of contigs (diamond) [non viral]
if (not -e $path_07_dmnd_non_viral_header_fa) {
    `touch $path_07_dmnd_non_viral_header_fa`;
}

my $n_dmnd_hits_non_viral = `grep -c '>' $path_07_dmnd_non_viral_header_fa`;
chomp($n_dmnd_hits_non_viral);
$n_dmnd_hits_non_viral = int($n_dmnd_hits_non_viral);

print "# Number of contigs (diamond) [non viral]\t".$n_dmnd_hits_non_viral."\n";

# Compute number of contigs (diamond) [no hits]
if (not -e $path_07_dmnd_no_hits_fa) {
    `touch $path_07_dmnd_no_hits_fa`;
}

my $n_dmnd_no_hits = `grep -c '>' $path_07_dmnd_no_hits_fa`;
chomp($n_dmnd_no_hits);
$n_dmnd_no_hits = int($n_dmnd_no_hits);

print "# Number of contigs (diamond) [no hits]\t".$n_dmnd_no_hits."\n";

# -----------------------------------------------------------------------

$current_time = Time::HiRes::gettimeofday();
$time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
$last_time = $current_time;

print STDOUT $time_msg;
print $time_msg;

######################################################################
## Build viral, non viral and no hits indexes ------------------------
######################################################################

$step_name = "Build viral, non viral and no hits indexes";

$time_msg = getStepTimebBeginMsg($exec_id, $step_name);
print STDOUT $time_msg;
print $time_msg;

# -----------------------------------------------------------------------

# 
# REVIEW: 2023-06-18 - Shouldn't this be in the previous 'block'?
# 
# Flagging sequence similarity types
`sed -i "s/>/>bN_/" $path_07_bN_analize_viral_header_fa`;
`sed -i "s/>/>bN_/" $path_07_bN_analize_non_viral_header_fa`;
`sed -i "s/>/>bX_/" $path_07_dmnd_viral_header_fa`;
`sed -i "s/>/>bX_/" $path_07_dmnd_non_viral_header_fa`;

# Merge viral and non viral stuff
`cat $path_07_bN_analize_viral_header_fa $path_07_dmnd_viral_header_fa > $path_07_all_viral_fa`;
`cat $path_07_bN_analize_non_viral_header_fa $path_07_dmnd_non_viral_header_fa > $path_07_all_non_viral_fa`;

# Compute number of contigs (all) [viral]
my $n_all_hits_viral = `grep -c '>' $path_07_all_viral_fa`;
chomp($n_all_hits_viral);
$n_all_hits_viral = int($n_all_hits_viral);
print "# Number of contigs (all) [viral]\t".$n_all_hits_viral."\n";

# Compute number of contigs (all) [non viral]
my $n_all_hits_non_viral = `grep -c '>' $path_07_all_non_viral_fa`;
chomp($n_all_hits_non_viral);
$n_all_hits_non_viral = int($n_all_hits_non_viral);
print "# Number of contigs (all) [non viral]\t".$n_all_hits_non_viral."\n";

# Compute number of contigs (all) [no hits]
my $n_all_no_hits = `grep -c '>' $path_07_dmnd_no_hits_fa`;
chomp($n_all_no_hits);
$n_all_no_hits = int($n_all_no_hits);
print "# Number of contigs (all) [no hits]\t".$n_all_no_hits."\n";

# Generate indexes for profiling
my $cmd = "";

if ($n_all_hits_viral) {
    $cmd = "bowtie-build $path_07_all_viral_fa $path_07_all_viral_fa";
    print "\nRunning: '$cmd'\n";
    `$cmd`;
}

if ($n_all_hits_non_viral) {
    $cmd = "bowtie-build $path_07_all_non_viral_fa $path_07_all_non_viral_fa";
    print "\nRunning: '$cmd'\n";
    `$cmd`;
}

if ($n_all_no_hits) {
    $cmd = "bowtie-build $path_07_dmnd_no_hits_header_fa $path_07_dmnd_no_hits_header_fa";
    print "\nRunning: '$cmd'\n";
    `$cmd`;
}

# -----------------------------------------------------------------------

$current_time = Time::HiRes::gettimeofday();
$time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
$last_time = $current_time;

print STDOUT $time_msg;
print $time_msg;

#######################################################################
### Align viral, non viral and no hits against unmapped reads ---------
#######################################################################

$step_name = "Align viral, non viral and no hits against unmapped reads";

$time_msg = getStepTimebBeginMsg($exec_id, $step_name);
print STDOUT $time_msg;
print $time_msg;

# -----------------------------------------------------------------------


if ($n_all_hits_viral) {
    print "\nAligning viral hits...\n";
    `bowtie -f -S -k 1 -p $process -v 1 $path_07_all_viral_fa $path_04_unmap_vector_bacters_fa > $path_07_all_viral_sam 2> $path_07_all_viral_log`;
}

if ($n_all_hits_non_viral) {
    print "\nAligning non viral hits...\n";
    `bowtie -f -S -k 1 -p $process -v 1 $path_07_all_non_viral_fa $path_04_unmap_vector_bacters_fa > $path_07_all_non_viral_sam 2> $path_07_all_non_viral_log`;
}

if ($n_all_no_hits) {
    print "\nAligning 'no hits'...\n";
    `bowtie -f -S -k 1 -p $process -v 1 $path_07_dmnd_no_hits_header_fa $path_04_unmap_vector_bacters_fa > $path_07_dmnd_no_hits_sam 2> $path_07_dmnd_no_hits_log`;
}

# -----------------------------------------------------------------------

$current_time = Time::HiRes::gettimeofday();
$time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
$last_time = $current_time;

print STDOUT $time_msg;
print $time_msg;

#######################################################################
### Extract & sort mapped reads from alignment .sam file results ------
#######################################################################

$step_name = "Extract & sort mapped reads from alignment .sam file results";

$time_msg = getStepTimebBeginMsg($exec_id, $step_name);
print STDOUT $time_msg;
print $time_msg;

# -----------------------------------------------------------------------

# Extract & sort from .sam only the mapped reads (those without flag '4')
if ($n_all_hits_viral) {
    print "Extracting & sorting reads .sam [viral] \n";
    `samtools view -S -h -F 4 $path_07_all_viral_sam > $path_07_all_viral_sam_mapped`;
    `samtools sort -O SAM -o $path_07_all_viral_sam_sort $path_07_all_viral_sam_mapped`;
    # samtools view -Sb $i > ${i}.bam
}

if ($n_all_hits_non_viral) {
    print "Extracting & sorting reads .sam [non viral] \n";
    `samtools view -S -h -F 4 $path_07_all_non_viral_sam > $path_07_all_non_viral_sam_mapped`;
    `samtools sort -O SAM -o $path_07_all_non_viral_sam_sort $path_07_all_non_viral_sam_mapped`;
    # samtools view -Sb $i > ${i}.bam
}

if ($n_all_no_hits) {
    print "Extracting & sorting reads .sam [no hit] \n";
    `samtools view -S -h -F 4 $path_07_dmnd_no_hits_sam > $path_07_dmnd_no_hits_sam_mapped`;
    `samtools sort -O SAM -o $path_07_dmnd_no_hits_sam_sort $path_07_dmnd_no_hits_sam_mapped`;
    # samtools view -Sb $i > ${i}.bam
}

# -----------------------------------------------------------------------

$current_time = Time::HiRes::gettimeofday();
$time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
$last_time = $current_time;

print STDOUT $time_msg;
print $time_msg;

#######################################################################
## Build small RNA profiles (for each contig & each feature) ----------
#######################################################################

$step_name = "Build small RNA profiles (for each contig & each feature)";

$time_msg = getStepTimebBeginMsg($exec_id, $step_name);
print STDOUT $time_msg;
print $time_msg;

# -----------------------------------------------------------------------

my $path_11_profile_viral = "$step11/smallrna_profiles_viral";
my $path_11_profile_non_viral = "$step11/smallrna_profiles_non_viral";
my $path_11_profile_no_hits = "$step11/smallrna_profiles_no_hits";

if (not -e $path_11_profile_viral) {
    `mkdir $path_11_profile_viral`;
}
if (not -e $path_11_profile_non_viral) {
    `mkdir $path_11_profile_non_viral`;
}
if (not -e $path_11_profile_no_hits) {
    `mkdir $path_11_profile_no_hits`;
}

print "\n Running 'plot mapping' for small RNA viral profiles...\n";

if ($n_all_hits_viral) {
    $cmd = "perl $path_plot_map_data_base_preference -sam $path_07_all_viral_sam_sort -s 18 -e 35 -fa $path_07_all_viral_fa -pace 1 -p $path_11_profile_viral/profile --profile --pattern -m 1 --keep";
    print("Plot mapping data per base preferences [viral] \n\t $cmd \n");
    `$cmd`;
}

if ($n_all_hits_non_viral) {
    $cmd = "perl $path_plot_map_data_base_preference -sam $path_07_all_non_viral_sam_sort -s 18 -e 35 -fa $path_07_all_non_viral_fa -pace 1 -p $path_11_profile_non_viral/profile --profile --pattern -m 1 --keep";
    print("Plot mapping data per base preferences [non viral] \n\t $cmd \n");
    `$cmd`;
}

if ($n_all_no_hits) {
    $cmd = "perl $path_plot_map_data_base_preference -sam $path_07_dmnd_no_hits_sam_sort -s 18 -e 35 -fa $path_07_dmnd_no_hits_header_fa -pace 1 -p $path_11_profile_no_hits/profile --profile --pattern -m 1 --keep";
    print("Plot mapping data per base preferences [no hit] \n\t $cmd \n");
    `$cmd`;
}

# -----------------------------------------------------------------------

$current_time = Time::HiRes::gettimeofday();
$time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
$last_time = $current_time;

print STDOUT $time_msg;
print $time_msg;

#######################################################################
### Generating Z-Scores & features matrices ---------------------------
#######################################################################

$step_name = "Generating Z-Scores & features matrices";

$time_msg = getStepTimebBeginMsg($exec_id, $step_name);
print STDOUT $time_msg;
print $time_msg;

# -----------------------------------------------------------------------

my $path_12_z_out_tab_log = "$step12/formatting.log";

my $path_12_viral_prefix = "$step12/viral";
my $path_12_viral_k10_sam = "$path_12_viral_prefix.v1.k10.sam"; # viral.v1.k10.sam
my $path_12_viral_strand_fa = "$path_12_viral_prefix.stranded.fasta"; # viral.stranded.fasta
my $path_12_viral_z_out_prefix = "$path_12_viral_prefix.stranded.out"; # saida.stranded
my $path_12_viral_z_out_tab = "$path_12_viral_z_out_prefix.zscore.tab"; # viral.stranded.out.zscore.tab

my $path_12_non_viral_prefix = "$step12/non_viral";
my $path_12_non_viral_k10_sam = "$path_12_non_viral_prefix.v1.k10.sam"; # non_viral.v1.k10.sam
my $path_12_non_viral_strand_fa = "$path_12_non_viral_prefix.stranded.fasta"; # non_viral.stranded.fasta
my $path_12_non_viral_out_prefix = "$path_12_non_viral_prefix.stranded.out"; # saida.stranded
my $path_12_non_viral_z_out_tab = "$path_12_non_viral_out_prefix.zscore.tab"; # non_viral.stranded.out.zscore.tab

my $path_12_no_hit_prefix = "$step12/no_hit";
my $path_12_no_hit_k10_sam = "$path_12_no_hit_prefix.v1.k10.sam"; # no_hit.v1.k10.sam
my $path_12_no_hit_strand_fa = "$path_12_no_hit_prefix.stranded.fasta"; # no_hit.stranded.fasta
my $path_12_no_hit_out_prefix = "$path_12_no_hit_prefix.stranded.out"; # saida.stranded
my $path_12_no_hit_z_out_tab = "$path_12_no_hit_out_prefix.zscore.tab"; # no_hit.stranded.out.zscore.tab

my $path_12_feat_matrix = "$step12/Zscore_and_features_matrix.tab";

my $z_score_feat_args = "";

if ($n_all_hits_viral) {
    
    print("Runnning sam 2 sam [viral] \n");
    `perl $path_sam_2_sam_stranded -sam $path_07_all_viral_sam_sort -r $path_04_unmap_vector_bacters_fa -fa $path_07_all_viral_fa -p $path_12_viral_prefix`;
    
    print("Runnning z-score [viral] \n");
    `perl $path_z_score_both_strands -sam $path_12_viral_k10_sam -fa $path_12_viral_strand_fa -p $path_12_viral_z_out_prefix`;

    $z_score_feat_args .= " --viral=$path_12_viral_z_out_tab";
}

if ($n_all_hits_non_viral) {
    
    print("Runnning sam 2 sam [non viral] \n");
    `perl $path_sam_2_sam_stranded -sam $path_07_all_non_viral_sam_sort -r $path_04_unmap_vector_bacters_fa -fa $path_07_all_non_viral_fa -p $path_12_non_viral_prefix`;
    
    print("Runnning z-score [non viral] \n");
    `perl $path_z_score_both_strands -sam $path_12_non_viral_k10_sam -fa $path_12_non_viral_strand_fa -p $path_12_non_viral_out_prefix`;

    $z_score_feat_args .= " --nonviral=$path_12_non_viral_z_out_tab";
}

if ($n_all_no_hits) {
    
    print("Runnning sam 2 sam [nohit] \n");
    `perl $path_sam_2_sam_stranded -sam $path_07_dmnd_no_hits_sam_sort -r $path_04_unmap_vector_bacters_fa -fa $path_07_dmnd_no_hits_header_fa -p $path_12_no_hit_prefix`;

    print("Runnning z-score [nohit] \n");
    `perl $path_z_score_both_strands -sam $path_12_no_hit_k10_sam -fa $path_12_no_hit_strand_fa -p $path_12_no_hit_out_prefix`;

    $z_score_feat_args .= " --nohit=$path_12_no_hit_z_out_tab";
}

if ($z_score_feat_args) {
    print "Generating .tab feature matrices...";
    $cmd = "Rscript $path_z_score_feature $z_score_feat_args --dir=$step12 > $path_12_z_out_tab_log";
    print("\n\t$cmd");
    `$cmd`;
}

# -----------------------------------------------------------------------

$current_time = Time::HiRes::gettimeofday();
$time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
$last_time = $current_time;

print STDOUT $time_msg;
print $time_msg;

#######################################################################
### Classifying virus × EVEs ------------------------------------------
#######################################################################

$step_name = "Classifying virus × EVEs";

$time_msg = getStepTimebBeginMsg($exec_id, $step_name);
print STDOUT $time_msg;
print $time_msg;

# -----------------------------------------------------------------------

my $path_13_eve_classif = "$step13/$exec_id-viral-eve.csv";

# my $cmd_eve = "python3 $path_eve_classif --input $path_12_feat_matrix --output $path_13_eve_classif --classifier ".PATH_CLASSIF_EVE." --verbose > ___foo.txt";
my $cmd_eve = "python3 $path_eve_classif --input $path_12_feat_matrix --output $path_13_eve_classif --classifier ".PATH_CLASSIF_EVE;

print "RUNING '$cmd_eve'...";
`$cmd_eve`;

# -----------------------------------------------------------------------

$current_time = Time::HiRes::gettimeofday();
$time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
$last_time = $current_time;

print STDOUT $time_msg;
print $time_msg;

#######################################################################

# -- THE END --
finishSuccesfully();
