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
use constant REF_DIAMOND_NR => "/small-rna-metavir/asset/diamond/nrcluster_tax.dmnd";#new
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

$0 -h

------------------------------------------------------
Args Description:

-fasta <reads.fa[.gz]>   : Input reads in FASTA format (no quality scores; .gz supported). Note: when using -fasta, quality trimming and FastQC steps are skipped.
-fastq <reads.fq|.fastq[.gz]> : Input reads in FASTQ format (compressed or not).FastQC and Trim Galore will be executed automatically before conversion to FASTA.
-hostgenome <reference .fasta> : host reference genome. No required when using -nohostfilter
-prefix <Output prefix>         : Output prefix folder name
-size <expected size of genome>: The expected size of the genome to detect
-si <size reads>	       		: Init range to use
-se <size reads>	       	    : End range to use
-process <number of process>   : number of process to use
-log <log file name>	       : log file name to storage the execution lines

-hash <hash length>	       	    : hash to be used in velvet assembly
-qual <reads .qual>            : Input quality file

-nohostfilter                      : Run directly the assembly without mapping to the host genome previously. Dispenses -hostgenome 
-nononviralprofiles            : Skip small RNA size profiles for non-viral contigs (saves time)

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
# my $log; # TODO: 2023-02-27 - Restablish the custom log file(s) option
my $hash;
my $clean;
my $nohostfilter;
my $large_index;
my $deg; # TODO: 2023-02-25 - Can we please call it 'degradation'?
my $help;
my $lib_prefix;
my $nononviralprofiles;

my $exec_id;

GetOptions("qual=s" => \$qual,
    "hostgenome=s" => \$hostgenome,
    "fasta=s" => \$fasta,
    "fastq=s" => \$fastq,
    "prefix=s" => \$lib_prefix,
    "size=s" => \$size,
    "hash=s" => \$hash,
    "si=s" => \$si,
    "se=s" => \$se,
    "process=s" => \$process,
    "clean!" => \$clean,
    "nohostfilter!" => \$nohostfilter, 
    "degradation!" => \$deg,
    "largeindex!" => \$large_index,
    "h!" => \$help,
    "exec-id=s" => \$exec_id,
    "nononviralprofiles!" => \$nononviralprofiles
);
# --- Auto-handle gzipped FASTA for -fasta input (Option 1: temporary decompress) ---
if (defined($fasta) && $fasta =~ /\.gz$/) {
    print "[INFO] Detected gzipped FASTA: $fasta\n";
    my $unzipped = $fasta;
    $unzipped =~ s/\.gz$//;
    my $cmd = "gunzip -c \"$fasta\" > \"$unzipped\"";
    my $rc = system($cmd);
    if ($rc != 0) {
        my $code = $rc >> 8;
        die "[ERROR] Could not decompress $fasta (exit $code)\n";
    }
    $fasta = $unzipped;
    print "[INFO] Using decompressed FASTA: $fasta\n";
}


if ($help) {
    die $usage;
}

    if (not(defined $fastq)) {
            die "\nGive a valid input file!\n ", $usage;
        }

        if (not(defined($qual)) and(not defined($fastq)) and(not defined($fasta))) {
            die "\nGive a valid input quality file name! \n", $usage;
        }
    


if (defined($large_index)) {
    $large_index = " --large-index ";
} else {
    $large_index = " ";
}

if (not(defined($exec_id))) {
    die "\nYou must name an ID for this execution! \n", $usage;
}

if ((not(defined($hostgenome))) and (not(defined($nohostfilter)))) {
    die "\nGive a valid input reference file (or use -nohostfilter to skip host filtering).\n", $usage;
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
my $hostref_str = defined($nohostfilter) ? "N/A (nohostfilter)" : $hostgenome;
my $runningDetails = "

-------------------------------------------
> Details:

Start Time: $time_start_str

> Reads: '$fasta';
> Reference: '$hostref_str';
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
my $step2		="$exec_dir/${lib_prefix}_02_filter_size_gaps_convertion";
my $step3		="$exec_dir/${lib_prefix}_03_mapping_vector";
my $step4		="$exec_dir/${lib_prefix}_04_getUnmapped";

my $step5_1_opt	="$exec_dir/${lib_prefix}_05_1_assembleUnmapped_opt";
my $step5_2_fix	="$exec_dir/${lib_prefix}_05_2_assembleUnmapped_fix";
my $step5_3_opt_fix = "$exec_dir/${lib_prefix}_05_3_assembleUnmapped_opt_fix";
my $step5_4_opt_20to23 = "$exec_dir/${lib_prefix}_05_4_assembleUnmapped_opt_20to23";
my $step5_5_opt_24to30 = "$exec_dir/${lib_prefix}_05_5_assembleUnmapped_opt_24to30";
my $step5_6_cap3  = "$exec_dir/${lib_prefix}_05_6_cap3";

my $step6		="$exec_dir/${lib_prefix}_06_blast";
my $step7		="$exec_dir/${lib_prefix}_07_reportBlast";
my $step11		="$exec_dir/${lib_prefix}_11_profiles";
my $step12		="$exec_dir/${lib_prefix}_12_z_score_small_rna_features";
my $step13		="$exec_dir/${lib_prefix}_13_virus_eve_classif";

# Utils scripts
my $path_utils = "/small-rna-metavir/src/utils";

my $path_warns = "$exec_dir/$exec_id.warn";

#my $path_filter_diamond = "$path_utils/filter_diamond.sh"; remover 
my $path_filter_diamond = "$path_utils/process_diamond_out6.sh";#new
my $path_filter_fasta_by_size = "$path_utils/filter_fasta_by_size.py";
my $path_plot_dist_per_base_by_reads = "$path_utils/plot-geral-dist-base-reads/plotGeralDistributionPerBaseByReads.pl";
my $path_plot_geral_byreads_fasta = "$path_utils/plot-geral-dist-base-reads/plotGeralDistributionPerBaseByReads_fasta.pl";
my $path_merge_contigs = "$path_utils/merge-contigs/mergeContigsNew.pl";
my $path_fix_cap3_contigs = "$path_utils/fixIdCap3Contigs.pl";
#my $path_filter_blast = "$path_utils/filterblast.pl"; remover se o blastn funcionar
my $path_filter_blast = "$path_utils/process_blastn_out6.sh"; #new
#my $path_analyse_contigs_blastn = "$path_utils/analyse-contigs-blastn/analyzeContigsFilterBlastn.pl";
#my $path_extract_seqs_no_hit_blast = "$path_utils/extract-seqs/extractSequencesNoHitBlast.pl";

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

my $path_02_trim_filtered_gt15_fa = "$step2/${lib_prefix}_trimmed_filtered_gt15.fasta";

if (defined($fastq)) {
    print "Processing fastq sequences...\n";
    print "\n\nRunning step 0 [ quality filter - Trim Galore ]\n";

    my $exec_fq_0 = "trim_galore --fastqc --length 18 --trim-n --max_n 0 -o $step2 -j 8 --dont_gzip $fastq";
    print "\nSTEP0\n\t$exec_fq_0\n";
    system($exec_fq_0) == 0 or die "[trim_galore] failed (exit $? >> 8)\n";

    # Now locate the (single) trimmed FASTQ produced
    my @fq_files = glob("$step2/*.fq");
    die "[ERROR] No trimmed FASTQ found in $step2\n"      if @fq_files == 0;
    die "[ERROR] Multiple .fq files found in $step2: @fq_files\n" if @fq_files > 1;

    my $path_02_trim_quality_fq = $fq_files[0];
    print "[INFO] Found trimmed FASTQ: $path_02_trim_quality_fq\n";

    # Convert fastq to fasta
    print "\n\nRunning step 2 [ converting fastq to fasta - fastq_to_fasta ]\n";
    my $exec_fq_2 = "fastq_to_fasta -Q 33 -i $path_02_trim_quality_fq -o $path_02_trim_filtered_gt15_fa";
    print "\nSTEP2\n\t$exec_fq_2\n";
    system($exec_fq_2) == 0 or die "[fastq_to_fasta] failed (exit $? >> 8)\n";

    -e $path_02_trim_filtered_gt15_fa
        or die "[ERROR] FASTA not created: $path_02_trim_filtered_gt15_fa\n";

    # [CLEAN] Remove trimmed FASTQ once converted to FASTA
    if (defined($clean) && defined($path_02_trim_quality_fq) && -e $path_02_trim_quality_fq) {
        unlink $path_02_trim_quality_fq or warn "[CLEAN] Could not remove $path_02_trim_quality_fq: $!";
    }

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

my $path_03_map_host_sam = "$step3/${lib_prefix}_mapped_host.v1.sam";
my $path_03_map_host_stats = "$step3/${lib_prefix}_mapping_host.stats";

my $path_04_unmap_vector_reads_fa = "$step4/${lib_prefix}_unmappedVectorReads.fasta";
my $path_04_unmap_vector_bacters_fa = "$step4/${lib_prefix}_unmappedVectorBacters.fasta";
my $path_04_unmap_trim_filter_fa = "$step4/${lib_prefix}_unmapped_trimmed_filtered.fasta";
my $path_04_unmap_trim_filter_20_23_fa = "$step4/${lib_prefix}_unmapped_trimmed_filtered.20-23.fasta";
my $path_04_unmap_trim_filter_24_30_fa = "$step4/${lib_prefix}_unmapped_trimmed_filtered.24-30.fasta";
my $path_04_reads_map_bacteria_log = "$step4/reads_mapped_to_bacteria.log";

# 
# REVIEW: 2023-03-01 - Shall we think of better names?
# 

my $mappedbac;
my $nReadsUnmapHostBac;
my $nReadsTrimmed;
# my $nReadsUnmapHost;

print "# Loading FASTA file ... \n";

if (defined($nohostfilter)) {

     # Mapping Host - filtered reads against bacters reference
    print "[MAPPING HOST-FILTERED READS AGAINST BACTERIAL GENOMES]... \n";
    my $exec5_1 = "bowtie -f -S -v 1 --un $path_04_unmap_vector_bacters_fa -k 1 -p $process --large-index ".REF_BACTERIA_GENOMES." $path_02_trim_filtered_gt15_fa > /dev/null 2>>$path_warns ";
    
    print "\n[STEP 05.1]\n\t $exec5_1\n";
    `$exec5_1`;

    $nReadsUnmapHostBac = `grep -c '>' $path_04_unmap_vector_bacters_fa`;
    chomp($nReadsUnmapHostBac);
    $nReadsTrimmed = `grep -c '>' $path_02_trim_filtered_gt15_fa`;
    chomp($nReadsTrimmed);
    $mappedbac = $nReadsTrimmed  - $nReadsUnmapHostBac;

    # Mapped reads Bacterial genomes
    # print metrics "# Reads mapped bacter\t".$mappedbac. # REVIEW: 2023-03-06 - What should we do with these 'special' logs?
    print "# Reads mapped bacter\t".$mappedbac."\n";
    
    # Pre processed reads
    # print metrics "# Preprocessed reads\t".$nReadsUnmapHostBac. # REVIEW: 2023-03-06 - What should we do with these 'special' logs?
    print "# Preprocessed reads\t".$nReadsUnmapHostBac."\n";
    
    print "\n PRE-PROCESSING FINISHED \n";
    
}


if (not defined($nohostfilter)) {

    if (not defined($fastq)) {

        my $cmd = "cp $fasta $path_02_trim_filtered_gt15_fa";

        print "[COPING $fasta TO $path_02_trim_filtered_gt15_fa]\n";
        `$cmd`;
        
        print "\n[STEP 03]\n\t $cmd\n";
    }
 
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

########## small RNA Profile dos reads trimados
print "[PLOT GERAL DISTRIBUTION READS TRIMMED LIBRARY]\n";
    my $exec_Lib_profile = "perl $path_plot_geral_byreads_fasta -fa $path_02_trim_filtered_gt15_fa  -s 15 -e 50 -p $step2/${lib_prefix}_trim_lib.v1  --plot";
    
    print "\n[STEP 03]\n\t $exec_Lib_profile\n";
    `$exec_Lib_profile`;


    # 
    # TODO: 2023-06-06 - Convert .sam into .bam
    # 

#O script desse plot ta configurado de um jeito que fica horrivel ateh 50 o plot, por hora, ficara soh 15 a 35 no pipeline
#lembrar que se arrumar aqui algum dia, tem que arrumar a parte de que coloca o rpefixo das libs no output
    #print "[PLOT GERAL DISTRIBUTION READS MAPPED HOST ]\n";
    #my $exec3_1 = "perl $path_plot_dist_per_base_by_reads -sam $path_03_map_host_sam  -s $si -e $se -p $step3/mapped_host.v1.$si.$se -norm $nReads --plot";
    
    #print "\n[STEP 03]\n\t $exec3_1\n";
    #`$exec3_1`;

    print "[PLOT GERAL DISTRIBUTION READS MAPPED HOST - $si - 50 nt ]\n";
    my $exec3_11 = "perl $path_plot_dist_per_base_by_reads -sam $path_03_map_host_sam  -s $si -e 50 -p $step3/${lib_prefix}_mapped_host.v1 -norm $nReads --plot";
    
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
# === STEP 02 SUMMARY (raw & trimmed) ===
my($n_raw_reads_02,$n_trimmed_reads_02 );
{
     $n_raw_reads_02     = "NA";
     $n_trimmed_reads_02 = "NA";

    if (defined $fasta) {
        # --- FASTA mode: both values equal ---
        if (-e $fasta && -s $fasta) {
            chomp($n_raw_reads_02     = `grep -c '>' "$fasta"`);
            chomp($n_trimmed_reads_02 = $n_raw_reads_02);
        }
    }
    else {
        # --- FASTQ mode: parse Trim Galore report for raw count ---
        my @reports = defined($step2) ? glob("$step2/*trimming_report.txt") : ();
        if (@reports) {
            my $report = $reports[0];
            if (-e $report && -s $report) {
                my $line = `grep 'Total reads processed:' "$report" | head -1`;
                if ($line =~ /Total\s+reads\s+processed:\s*([\d,]+)/) {
                    ($n_raw_reads_02 = $1) =~ s/,//g;  # remove commas
                }
            }
        }

        # --- trimmed count from filtered FASTA ---
        if (defined $path_02_trim_filtered_gt15_fa && -e $path_02_trim_filtered_gt15_fa && -s $path_02_trim_filtered_gt15_fa) {
            chomp($n_trimmed_reads_02 = `grep -c '>' "$path_02_trim_filtered_gt15_fa"`);
        }
    }

    print "[SUMMARY] Step02 -> raw=$n_raw_reads_02 trimmed=$n_trimmed_reads_02\n";

}


# === STEP 03 SUMMARY (reads aligned to host) ===
my $n_reads_host_03;
{
    $n_reads_host_03 = "NA";

    if (defined $path_03_map_host_sam && -e $path_03_map_host_sam && -s $path_03_map_host_sam) {
        chomp($n_reads_host_03 = `samtools view -c -F 4 "$path_03_map_host_sam" 2>/dev/null`);
    }

    print "[SUMMARY] Step03 -> reads_aligned_to_host=$n_reads_host_03\n";
}

# === POST-STEP03: convert *_mapped_host.v1.sam -> .bam ===
{
    my $thr = defined($process) ? $process : 8;
    if (defined $step3 && -d $step3) {
        my @sams = glob("$step3/*_mapped_host.v1.sam");
        if (@sams) {
            print "[STEP03->BAM] threads=$thr ; files=", scalar(@sams), "\n";
            for my $sam (@sams) {
                next unless -s $sam;
                (my $bam = $sam) =~ s/\.sam$/.bam/i;
                my $cmd = "samtools view -@ $thr -Sb '$sam' -o '$bam'";
                print "[SAM->BAM] $cmd\n";
                my $rc = system($cmd);
                if ($rc == 0 && -s $bam) { unlink $sam or warn "[WARN] $sam: $!\n"; }
                else { warn "[WARN] samtools view failed for $sam (rc=$rc)\n"; }
            }
        }
    }
}

########## small RNA Profile dos reads unmapped (step4)
if (defined $nohostfilter) {
    print "[PLOT GERAL DISTRIBUTION UNMAPPED BACTERS ONLY (-nohostfilter)]\n";
    my $exec_unm_bac = "perl $path_plot_geral_byreads_fasta -fa $path_04_unmap_vector_bacters_fa -s 15 -e 50 -p $step4/${lib_prefix}_unmapped_bacters.v1 --plot";
    print "\n[STEP 04]\n\t $exec_unm_bac\n";
    `$exec_unm_bac`;
} else {
    print "[PLOT GERAL DISTRIBUTION VECTOR UNMAPPED READS]\n";
    my $exec_unm_reads = "perl $path_plot_geral_byreads_fasta -fa $path_04_unmap_vector_reads_fa -s 15 -e 50 -p $step4/${lib_prefix}_unmapped_vector.v1 --plot";
    print "\n[STEP 04]\n\t $exec_unm_reads\n";
    `$exec_unm_reads`;

    print "[PLOT GERAL DISTRIBUTION BACTER UNMAPPED READS]\n";
    my $exec_unm_bac = "perl $path_plot_geral_byreads_fasta -fa $path_04_unmap_vector_bacters_fa -s 15 -e 50 -p $step4/${lib_prefix}_unmapped_bacters.v1 --plot";
    print "\n[STEP 04]\n\t $exec_unm_bac\n";
    `$exec_unm_bac`;

    
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


# === POST-STEP04: compact 02/trimmed_filtered_gt15.fasta ===
{
    if (defined $step2 && -e $path_02_trim_filtered_gt15_fa && -s $path_02_trim_filtered_gt15_fa) {
        print "[GZIP] $path_02_trim_filtered_gt15_fa\n";
        my $rc = system("gzip -f -9 '$path_02_trim_filtered_gt15_fa'");
        warn "[WARN] gzip failed for $path_02_trim_filtered_gt15_fa (rc=$rc)\n" if $rc != 0;  # gzip removes the .fasta on success
    }
}


# === STEP 04 SUMMARY (bacteria + filtered categories) ===
my ($n_reads_bacter_04, $n_unmap_bac_04, $n_unmap_filter_04, $n_unmap_20_23_04,$n_unmap_24_30_04);

{
     $n_reads_bacter_04  = "NA";
     $n_unmap_bac_04     = "NA";
     $n_unmap_filter_04  = "NA";
     $n_unmap_20_23_04   = "NA";
     $n_unmap_24_30_04   = "NA";

    # ---------- unmapped after bacteria ----------
    if (defined $path_04_unmap_vector_bacters_fa && -e $path_04_unmap_vector_bacters_fa && -s $path_04_unmap_vector_bacters_fa) {
        chomp($n_unmap_bac_04 = `grep -c '^>' "$path_04_unmap_vector_bacters_fa" 2>/dev/null`);
    }

    # ---------- unmapped after general filtering ----------
    if (defined $path_04_unmap_trim_filter_fa && -e $path_04_unmap_trim_filter_fa && -s $path_04_unmap_trim_filter_fa) {
        chomp($n_unmap_filter_04 = `grep -c '^>' "$path_04_unmap_trim_filter_fa" 2>/dev/null`);
    }

    # ---------- reads 20-23 nt ----------
    if (defined $path_04_unmap_trim_filter_20_23_fa && -e $path_04_unmap_trim_filter_20_23_fa && -s $path_04_unmap_trim_filter_20_23_fa) {
        chomp($n_unmap_20_23_04 = `grep -c '^>' "$path_04_unmap_trim_filter_20_23_fa" 2>/dev/null`);
    }

    # ---------- reads 24-30 nt ----------
    if (defined $path_04_unmap_trim_filter_24_30_fa && -e $path_04_unmap_trim_filter_24_30_fa && -s $path_04_unmap_trim_filter_24_30_fa) {
        chomp($n_unmap_24_30_04 = `grep -c '^>' "$path_04_unmap_trim_filter_24_30_fa" 2>/dev/null`);
    }

    # ---------- mapped to bacteria ----------
    if (defined $n_unmap_bac_04 && $n_unmap_bac_04 ne "") {
        my $base = undef;
        if ($nohostfilter) {
            # -nohostfilter: base = total trimmed reads
            $base = $n_trimmed_reads_02 if defined $n_trimmed_reads_02 && $n_trimmed_reads_02 ne "NA";
        } else {
            # with host filter: base = unmapped after host filtering
            if (defined $path_04_unmap_vector_reads_fa && -e $path_04_unmap_vector_reads_fa && -s $path_04_unmap_vector_reads_fa) {
                chomp($base = `grep -c '^>' "$path_04_unmap_vector_reads_fa" 2>/dev/null`);
            }
        }

        if (defined $base && $base ne "") {
            my $diff = $base - $n_unmap_bac_04;
            $diff = 0 if $diff < 0;
            $n_reads_bacter_04 = $diff;
        }
    }

    print "[SUMMARY] Step04 -> reads_aligned_to_bacter=$n_reads_bacter_04\t".
          "unmap_bac=$n_unmap_bac_04\tfiltered=$n_unmap_filter_04\t20_23=$n_unmap_20_23_04\t24_30=$n_unmap_24_30_04\n";
}

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
# [CLEAN] Remove 05_3 run directories
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

    if (!$__DONT_USE_it_yet_n_contigs_gt200) {
    
    my $err_msg = $countAssembledContigs
        ? "No contigs >= 200nt!"
        : "No contigs assembled!";

    my $final_msg = "\n\n -- $err_msg -- \n\n";
    finishSuccesfully($final_msg);
}

$countAssembledContigs = $__DONT_USE_it_yet_n_contigs_gt200;





# [CLEAN] Size-bin FASTAs no longer needed after CAP3 and length filtering
    if (defined($clean) && -e $path_04_unmap_trim_filter_20_23_fa) {
        unlink $path_04_unmap_trim_filter_20_23_fa or warn "[CLEAN] Could not remove $path_04_unmap_trim_filter_20_23_fa: $!";
    }
    if (defined($clean) && -e $path_04_unmap_trim_filter_24_30_fa) {
        unlink $path_04_unmap_trim_filter_24_30_fa or warn "[CLEAN] Could not remove $path_04_unmap_trim_filter_24_30_fa: $!";
    }

}


# === STEP 05 SUMMARY (contigs > 200 bp) ===
my $n_contigs_gt200_05;
{
    $n_contigs_gt200_05 = "NA";

    if (defined $path_05_5_cap3_gt200_fa && -e $path_05_5_cap3_gt200_fa && -s $path_05_5_cap3_gt200_fa) {
        chomp($n_contigs_gt200_05 = `grep -c '^>' "$path_05_5_cap3_gt200_fa" 2>/dev/null`);
    }

    print "[SUMMARY] Step05 -> contigs_gt200=$n_contigs_gt200_05\n";
}
# Arrumar esse bloco se funcionar
# [CLEAN] Remove 05_1 run directories
if (defined($clean) && -d $path_05_1_opt_run1_dir) { system("rm -rf '$path_05_1_opt_run1_dir'") == 0 or warn "[CLEAN] Could not remove dir $path_05_1_opt_run1_dir: $!"; }
if (defined($clean) && -d $path_05_1_opt_run2_dir) { system("rm -rf '$path_05_1_opt_run2_dir'") == 0 or warn "[CLEAN] Could not remove dir $path_05_1_opt_run2_dir: $!"; }

# [CLEAN] Remove 05_2 run directories
if (defined($clean) && -d $path_05_2_fix_run1_dir) { system("rm -rf '$path_05_2_fix_run1_dir'") == 0 or warn "[CLEAN] Could not remove dir $path_05_2_fix_run1_dir: $!"; }
if (defined($clean) && -d $path_05_2_fix_run2_dir) { system("rm -rf '$path_05_2_fix_run2_dir'") == 0 or warn "[CLEAN] Could not remove dir $path_05_2_fix_run2_dir: $!"; }

if (defined($clean) && -d $path_05_3_opt_fix_run1_dir) { system("rm -rf '$path_05_3_opt_fix_run1_dir'") == 0 or warn "[CLEAN] Could not remove dir $path_05_3_opt_fix_run1_dir: $!"; }
if (defined($clean) && -d $path_05_3_opt_fix_run2_dir) { system("rm -rf '$path_05_3_opt_fix_run2_dir'") == 0 or warn "[CLEAN] Could not remove dir $path_05_3_opt_fix_run2_dir: $!"; }

# [CLEAN] Remove 05_4 (20-23 nt) run directories
if (defined($clean) && -d $path_05_4_opt_20_23_run1_dir) { system("rm -rf '$path_05_4_opt_20_23_run1_dir'") == 0 or warn "[CLEAN] Could not remove dir $path_05_4_opt_20_23_run1_dir: $!"; }
if (defined($clean) && -d $path_05_4_opt_20_23_run2_dir) { system("rm -rf '$path_05_4_opt_20_23_run2_dir'") == 0 or warn "[CLEAN] Could not remove dir $path_05_4_opt_20_23_run2_dir: $!"; }

# [CLEAN] Remove 24–30 assembly run directories (if they exist)
    if (defined($clean) && -d "$step5_5_opt_24to30/run1") {
        system("rm -rf '$step5_5_opt_24to30/run1'") == 0 or warn "[CLEAN] Could not remove dir $step5_5_opt_24to30/run1: $!";
    }
    if (defined($clean) && -d "$step5_5_opt_24to30/run2") {
        system("rm -rf '$step5_5_opt_24to30/run2'") == 0 or warn "[CLEAN] Could not remove dir $step5_5_opt_24to30/run2: $!";
    }

# === ID PREFIXING for assembled contigs (once, before BLAST/mapping) ===
# Keeps default flow; no new globals; idempotent (won't double-prefix).
for my $fa (
    $path_05_1_opt_contigs_final_fa,
    $path_05_2_fix_contigs_final_fa,
    $path_05_3_opt_fix_contigs_final_fa,
    $path_05_4_opt_20_23_contigs_final_fa,
    $path_05_5_cap3_final_24_30_fa,
    $path_05_6_cap3_all_fa,
    $path_05_5_cap3_gt200_fa,
    $path_05_5_cap3_gt50_fa
) {
    next unless defined $fa && -e $fa && -s $fa;
    my $tmp = "$fa.__tmp";
    open my $IN,  '<', $fa  or die "[ERROR] Can't open $fa: $!\n";
    open my $OUT, '>', $tmp or die "[ERROR] Can't write $tmp: $!\n";
    while (<$IN>) {
        if (/^>(\S+)(.*)$/) {
            if (index($1, "${lib_prefix}_") == 0) {
                print $OUT $_;                           # already prefixed
            } else {
                print $OUT '>' . $lib_prefix . '_' . $1 . $2 . "\n";
            }
        } else {
            print $OUT $_;
        }
    }
    close $IN; close $OUT;
    rename $tmp, $fa or die "[ERROR] Rename failed $tmp -> $fa: $!\n";
    print "[PREFIX] Applied ${lib_prefix}_ to headers in $fa\n";
}


# -----------------------------------------------------------------------

$current_time = Time::HiRes::gettimeofday();
$time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
$last_time = $current_time;

print STDOUT $time_msg;
print $time_msg;

# -----------------------------------------------------------------------

# === POST-STEP05: compact unmapped FASTAs in step4 ===
{
    if (defined $step4 && -d $step4) {
        for my $f ("$path_04_unmap_vector_reads_fa",
                   "$path_04_unmap_trim_filter_fa") {
            next unless -e $f && -s $f;
            print "[GZIP] $f\n";
            my $rc = system("gzip -f -9 '$f'");
            warn "[WARN] gzip failed for $f (rc=$rc)\n" if $rc != 0;
        }
    }
}

#######################################################################
### Blastn ------------------------------------------------------------
#######################################################################

$step_name = "Blastn";

$time_msg = getStepTimebBeginMsg($exec_id, $step_name);
print STDOUT $time_msg;
print $time_msg;

# -----------------------------------------------------------------------

my $path_06_blastn_no_hit_1e5_fa = "$step6/contigs_unaligned_blastn.fasta"; #remover
my $path_06_blastn_out6 = "$step6/blastN_gt200_AllHits_outfmt6.tab"; #new

my $path_06_bN_analize_viral_fa = "$step6/contigs_viral_BestHits_blastn.fasta"; #new


my $path_06_bN_analize_contigs_fa = "$step6/contigs_gt200_blastn_correct_strand.fasta"; #new
my $path_06_bN_analize_non_viral_fa = "$step6/contigs_nonviral_BestHits_blastn.fasta"; #new

my $path_07_dmnd_log = "$step7/diamond_gt200_AllHits.log";#new
my $path_07_dmnd_hits_fa = "$step7/diamond_aligned.fasta";#new
my $path_07_dmnd_out = "$step7/diamond_gt200_AllHits_outfmt6.tab";#new

my $path_07_dmnd_viral_header_fa = "$step7/contigs_viral_BestHits_diamond.fasta";#new
my $path_07_dmnd_non_viral_header_fa = "$step7/contigs_nonviral_BestHits_diamond.fasta";#new

my $path_07_dmnd_no_hits_prefix = "$step7/contigs_nohits_FINAL_diamond";#new
my $path_07_dmnd_no_hits_fa = "$step7/diamond_unaligned.fasta";#new
my $path_07_dmnd_no_hits_fa_FINAL = "$step7/contigs_nohits_FINAL_diamond.fasta";#new

my $path_07_dmnd_no_hits_log = "${path_07_dmnd_no_hits_prefix}_bowtie.log";
my $path_07_dmnd_no_hits_sam = "$path_07_dmnd_no_hits_prefix.sam";
my $path_07_dmnd_no_hits_sam_mapped = "$path_07_dmnd_no_hits_prefix.mapped.sam";
my $path_07_dmnd_no_hits_sam_sort = "$path_07_dmnd_no_hits_prefix.mapped.sort.sam";

my $path_07_all_viral_prefix = "$step7/${lib_prefix}_all_viral_hits";
my $path_07_all_viral_fa = "$path_07_all_viral_prefix.fasta";
my $path_07_all_viral_log = "${path_07_all_viral_prefix}_bowtie.log";
my $path_07_all_viral_sam_mapped = "$path_07_all_viral_prefix.mapped.sam";
my $path_07_all_viral_sam_sort = "$path_07_all_viral_prefix.mapped.sort.sam";

my $path_07_all_non_viral_prefix = "$step7/${lib_prefix}_all_non_viral_hits";
my $path_07_all_non_viral_fa = "$path_07_all_non_viral_prefix.fasta";
my $path_07_all_non_viral_log = "${path_07_all_non_viral_prefix}_bowtie.log";
my $path_07_all_non_viral_sam_mapped = "$path_07_all_non_viral_prefix.mapped.sam";
my $path_07_all_non_viral_sam_sort = "$path_07_all_non_viral_prefix.mapped.sort.sam";

my $path_07_all_viral_sam = "$path_07_all_viral_prefix.sam";
my $path_07_all_non_viral_sam = "$path_07_all_non_viral_prefix.sam";


print "\n[BlastN contigs gt 200]\n";
print "\t#Running step 10_111 [ Blast against NT - blast+ blastn ]\n";
#my $exec10_111 = "blastn -query $path_05_5_cap3_gt200_fa -db ".REF_BLAST_DB_NT."/nt -num_descriptions 5 -num_alignments 5 -evalue 1e-5 -out $path_06_blastn_merge_gt200_1e5  -num_threads $process"; #remover se o blastn funcionar
my $exec10_111 = "blastn -query $path_05_5_cap3_gt200_fa -db ".REF_BLAST_DB_NT."/core_nt  -num_alignments 5 -evalue 1e-5 -out $path_06_blastn_out6 -outfmt '6 qseqid qlen qstart qend length sseqid slen sstart send pident qcovs evalue bitscore frames sframe sstrand stitle staxid' -num_threads $process"; #new

print "\nSTEP10_111\n\t $exec10_111\n";`$exec10_111`;

print "\t#Running filterblast...\n";
#my $exec10_112 = "perl $path_filter_blast -b $path_06_blastn_merge_gt200_1e5 -evalue 1e-5 --best --desc > $path_07_blastn_1e5_report"; remover
my $exec10_112 = "$path_filter_blast -f $path_05_5_cap3_gt200_fa -t $path_06_blastn_out6 -o $step6 -u $path_utils";#new

print "\nSTEP10_112\n\t $exec10_112\n";
`$exec10_112`;


my $n_blastn_hits = `grep -c '>' $path_06_bN_analize_contigs_fa`;
chomp($n_blastn_hits);
$n_blastn_hits = int($n_blastn_hits);
print "\n# Number of contigs (blastN) [hits]\t".$n_blastn_hits."\n";

my $n_blastn_hits_virus = `grep -c '>' $path_06_bN_analize_viral_fa`;
chomp($n_blastn_hits_virus);
$n_blastn_hits_virus = int($n_blastn_hits_virus);
print "\n# Number of contigs (blastN) [viral]\t".$n_blastn_hits_virus."\n";

my $n_blastn_hits_non_viral = `grep -c '>' $path_06_bN_analize_non_viral_fa`;
chomp($n_blastn_hits_non_viral);
$n_blastn_hits_non_viral = int($n_blastn_hits_non_viral);
print "\n# Number of contigs (blastN) [non viral]\t".$n_blastn_hits_non_viral."\n";

my $n_blastn_no_hits = `grep -c '>' $path_06_blastn_no_hit_1e5_fa`;
chomp($n_blastn_no_hits);
$n_blastn_no_hits = int($n_blastn_no_hits);
print "# Number of contigs (blastN) [no hits]\t".$n_blastn_no_hits."\n";

#`cat $path_07_bN_analize_viral_fa | perl -pi -e 's/>(\\S+) (\\S+) (\\S+) (\\S+).+/>blastN_\$1_\$2_\$3_\$4/g' > $path_07_blastn_virus_fa`; ##Remove after implement new blast

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

    my $exec9 = "diamond blastx -q $path_06_blastn_no_hit_1e5_fa -d ".REF_DIAMOND_NR." -k 10 -p $process -e 0.001 -f 6 qseqid qlen qstart qend qcovhsp length sseqid slen sstart send scovhsp pident evalue bitscore qstrand qframe stitle staxids -c 1 -b 20 --very-sensitive -o $path_07_dmnd_out --un $path_07_dmnd_no_hits_fa --unfmt fasta --al $path_07_dmnd_hits_fa --alfmt fasta 2> $path_07_dmnd_log";#new

    print "\nSTEP9\n\t $exec9\n";
    `$exec9`;

    print "\t# Filtering Diamond results... ]\n";   
    #my $exec9_11 = "$path_filter_diamond -f $path_07_dmnd_hits_fa -o $path_07_dmnd_out -d $step7";
    my $exec9_11 = "$path_filter_diamond -f $path_07_dmnd_hits_fa -t $path_07_dmnd_out -o $step7 -u $path_utils";#new
 
    print "\nSTEP9_11\n\t $exec9_11\n";
    `$exec9_11`;

}

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
if (not -e $path_07_dmnd_no_hits_fa_FINAL) {
    `touch $path_07_dmnd_no_hits_fa_FINAL`;
}

my $n_dmnd_no_hits = `grep -c '>' $path_07_dmnd_no_hits_fa_FINAL`;
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

# Merge viral and non viral stuff
`cat $path_06_bN_analize_viral_fa $path_07_dmnd_viral_header_fa > $path_07_all_viral_fa`;
`cat $path_06_bN_analize_non_viral_fa $path_07_dmnd_non_viral_header_fa > $path_07_all_non_viral_fa`;

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
my $n_all_no_hits = `grep -c '>' $path_07_dmnd_no_hits_fa_FINAL`;
chomp($n_all_no_hits);
$n_all_no_hits = int($n_all_no_hits);
print "# Number of contigs (all) [no hits]\t".$n_all_no_hits."\n";

# Generate indexes for profiling
my $cmd = "";

if ($n_all_hits_viral) {
    $cmd = "bowtie-build --threads $process $path_07_all_viral_fa $path_07_all_viral_fa";
    print "\nRunning: '$cmd'\n";
    `$cmd`;
}

if ($n_all_hits_non_viral) {
    $cmd = "bowtie-build --threads $process $path_07_all_non_viral_fa $path_07_all_non_viral_fa";
    print "\nRunning: '$cmd'\n";
    `$cmd`;
}

if ($n_all_no_hits) {
    $cmd = "bowtie-build --threads $process $path_07_dmnd_no_hits_fa_FINAL $path_07_dmnd_no_hits_fa_FINAL";
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
    `bowtie -f -S -k 1 -p $process -v 1 $path_07_dmnd_no_hits_fa_FINAL $path_04_unmap_vector_bacters_fa > $path_07_dmnd_no_hits_sam 2> $path_07_dmnd_no_hits_log`;
}

# -----------------------------------------------------------------------

$current_time = Time::HiRes::gettimeofday();
$time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
$last_time = $current_time;

print STDOUT $time_msg;
print $time_msg;


######## Renaming files folder 5
# ---- Post-step05.6 (CAP3): prefix CAP3 outputs in $step5_6_cap3
{
    my @targets = qw(
        all_contigs.fasta
        all_contigs.fasta.cap.ace
        all_contigs.fasta.cap.contigs
        all_contigs.fasta.cap.contigs.links
        all_contigs.fasta.cap.contigs.qual
        all_contigs.fasta.cap.info
        all_contigs.fasta.cap.singlets
        contigs_merged.final.contigs
        contigs_merged.final.fasta
        contigs_merged.final.gt50.fasta
        contigs_merged.final.gt200.fasta
        log.cap3
    );

    for my $fname (@targets) {
        my $src = "$step5_6_cap3/$fname";
        next unless -e $src;
        next if $fname =~ /^\Q${lib_prefix}_\E/;
        my $dst = "$step5_6_cap3/${lib_prefix}_$fname";
        system("mv", "--", $src, $dst);
    }
}

##### Renaming files folder 6

# ---- Post-step06 (BLASTN): prefix outputs in $step6
{
    my @targets = qw(
        BestHits_blastn.tab
        blastN_gt200_AllHits_outfmt6.tab
        blastn_gt200_AllHits_outfmt6_TAX.tab
        contigs_gt200_blastn_correct_strand.fasta
        contigs_nonviral_BestHits_blastn.fasta
        contigs_unaligned_blastn.fasta
        contigs_viral_BestHits_blastn.fasta
        nonviral_AllHits_blastn.tab
        nonviral_BestHits_blastn.tab
        ranks_taxids_blast.tab
        viral_AllHits_blastn.tab
        viral_BestHits_blastn.tab
    );

    for my $fname (@targets) {
        my $src = "$step6/$fname";
        next unless -e $src;
        next if $fname =~ /^\Q${lib_prefix}_\E/;
        my $dst = "$step6/${lib_prefix}_$fname";
        system("mv", "--", $src, $dst);
    }
}

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
    `samtools view -S -h -F 4 -@ $process $path_07_all_viral_sam > $path_07_all_viral_sam_mapped`;
    `samtools sort -@ $process -O SAM -o $path_07_all_viral_sam_sort $path_07_all_viral_sam_mapped`;
    # samtools view -Sb $i > ${i}.bam
}

if ($n_all_hits_non_viral) {
    print "Extracting & sorting reads .sam [non viral] \n";
    `samtools view -S -h -F 4 -@ $process $path_07_all_non_viral_sam > $path_07_all_non_viral_sam_mapped`;
    `samtools sort -@ $process -O SAM -o $path_07_all_non_viral_sam_sort $path_07_all_non_viral_sam_mapped`;
    # samtools view -Sb $i > ${i}.bam
}

if ($n_all_no_hits) {
    print "Extracting & sorting reads .sam [no hit] \n";
    `samtools view -S -h -F 4 -@ $process $path_07_dmnd_no_hits_sam > $path_07_dmnd_no_hits_sam_mapped`;
    `samtools sort -@ $process -O SAM -o $path_07_dmnd_no_hits_sam_sort $path_07_dmnd_no_hits_sam_mapped`;
    # samtools view -Sb $i > ${i}.bam
}

# === DECLARE SUMMARY VARIABLES (STEP 07: mapped reads per class) ===
my ($n_reads_viral_07, $n_reads_non_viral_07, $n_reads_no_hits_07);
# === STEP 07 SUMMARY (reads mapped to contigs by class) ===
{
    $n_reads_viral_07     = "NA";
    $n_reads_non_viral_07 = "NA";
    $n_reads_no_hits_07   = "NA";

    # ----- viral -----
    if (defined $path_07_all_viral_sam_mapped && -e $path_07_all_viral_sam_mapped && -s $path_07_all_viral_sam_mapped) {
        chomp($n_reads_viral_07 = `samtools view -c "$path_07_all_viral_sam_mapped" 2>/dev/null`);
    }

    # ----- non viral -----
    if (defined $path_07_all_non_viral_sam_mapped && -e $path_07_all_non_viral_sam_mapped && -s $path_07_all_non_viral_sam_mapped) {
        chomp($n_reads_non_viral_07 = `samtools view -c "$path_07_all_non_viral_sam_mapped" 2>/dev/null`);
    }

    # ----- no hits -----
    if (defined $path_07_dmnd_no_hits_sam_mapped && -e $path_07_dmnd_no_hits_sam_mapped && -s $path_07_dmnd_no_hits_sam_mapped) {
        chomp($n_reads_no_hits_07 = `samtools view -c "$path_07_dmnd_no_hits_sam_mapped" 2>/dev/null`);
    }

    print "[SUMMARY] Step07 -> reads_viral=$n_reads_viral_07\treads_non_viral=$n_reads_non_viral_07\treads_no_hits=$n_reads_no_hits_07\n";
}




########## General small RNA Profiles dos arquivos SAM em step7

# 1) no_hits
print "[PLOT GERAL DISTRIBUTION SAM no_hits]\n";
my $exec_sam_nohits = "perl $path_plot_dist_per_base_by_reads -sam $path_07_dmnd_no_hits_sam_sort -s 15 -e 50 -p $step7/${lib_prefix}_no_hits --plot";
print "\n[STEP 07]\n\t $exec_sam_nohits\n";
`$exec_sam_nohits`;

# 2) all viral
print "[PLOT GERAL DISTRIBUTION SAM all_viral]\n";
my $exec_sam_viral = "perl $path_plot_dist_per_base_by_reads -sam $path_07_all_viral_sam_sort -s 15 -e 50 -p $step7/${lib_prefix}_all_viral --plot";
print "\n[STEP 07]\n\t $exec_sam_viral\n";
`$exec_sam_viral`;

# 3) all non-viral
print "[PLOT GERAL DISTRIBUTION SAM all_non_viral]\n";
my $exec_sam_nonviral = "perl $path_plot_dist_per_base_by_reads -sam $path_07_all_non_viral_sam_sort -s 15 -e 50 -p $step7/${lib_prefix}_all_non_viral --plot";
print "\n[STEP 07]\n\t $exec_sam_nonviral\n";
`$exec_sam_nonviral`;



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

my $path_11_profile_viral = "$step11/${lib_prefix}_smallrna_profiles_viral";
my $path_11_profile_non_viral = "$step11/${lib_prefix}_smallrna_profiles_non_viral";
my $path_11_profile_no_hits = "$step11/${lib_prefix}_smallrna_profiles_no_hits";

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

if (!$nononviralprofiles && $n_all_hits_non_viral) {
    $cmd = "perl $path_plot_map_data_base_preference -sam $path_07_all_non_viral_sam_sort -s 18 -e 35 -fa $path_07_all_non_viral_fa -pace 1 -p $path_11_profile_non_viral/profile --profile --pattern -m 1 --keep";
    print("Plot mapping data per base preferences [non viral] \n\t $cmd \n");
    `$cmd`;
}
elsif ($nononviralprofiles) {
    print("[INFO] Skipping small RNA profiles for non-viral contigs (-nononviralprofiles)\n");
}

if ($n_all_no_hits) {
    $cmd = "perl $path_plot_map_data_base_preference -sam $path_07_dmnd_no_hits_sam_sort -s 18 -e 35 -fa $path_07_dmnd_no_hits_fa_FINAL -pace 1 -p $path_11_profile_no_hits/profile --profile --pattern -m 1 --keep";
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

my $path_12_viral_prefix = "$step12/${lib_prefix}_viral";
my $path_12_viral_k10_sam = "$path_12_viral_prefix.v1.k10.sam"; # viral.v1.k10.sam
my $path_12_viral_strand_fa = "$path_12_viral_prefix.stranded.fasta"; # viral.stranded.fasta
my $path_12_viral_z_out_prefix = "$path_12_viral_prefix.stranded.out"; # saida.stranded
my $path_12_viral_z_out_tab = "$path_12_viral_z_out_prefix.zscore.tab"; # viral.stranded.out.zscore.tab

my $path_12_non_viral_prefix = "$step12/${lib_prefix}_non_viral";
my $path_12_non_viral_k10_sam = "$path_12_non_viral_prefix.v1.k10.sam"; # non_viral.v1.k10.sam
my $path_12_non_viral_strand_fa = "$path_12_non_viral_prefix.stranded.fasta"; # non_viral.stranded.fasta
my $path_12_non_viral_out_prefix = "$path_12_non_viral_prefix.stranded.out"; # saida.stranded
my $path_12_non_viral_z_out_tab = "$path_12_non_viral_out_prefix.zscore.tab"; # non_viral.stranded.out.zscore.tab

my $path_12_no_hit_prefix = "$step12/${lib_prefix}_no_hit";
my $path_12_no_hit_k10_sam = "$path_12_no_hit_prefix.v1.k10.sam"; # no_hit.v1.k10.sam
my $path_12_no_hit_strand_fa = "$path_12_no_hit_prefix.stranded.fasta"; # no_hit.stranded.fasta
my $path_12_no_hit_out_prefix = "$path_12_no_hit_prefix.stranded.out"; # saida.stranded
my $path_12_no_hit_z_out_tab = "$path_12_no_hit_out_prefix.zscore.tab"; # no_hit.stranded.out.zscore.tab

my $path_12_feat_matrix = "$step12/${lib_prefix}_Zscore_and_features_matrix.tab";

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
    `perl $path_sam_2_sam_stranded -sam $path_07_dmnd_no_hits_sam_sort -r $path_04_unmap_vector_bacters_fa -fa $path_07_dmnd_no_hits_fa_FINAL -p $path_12_no_hit_prefix`;

    print("Runnning z-score [nohit] \n");
    `perl $path_z_score_both_strands -sam $path_12_no_hit_k10_sam -fa $path_12_no_hit_strand_fa -p $path_12_no_hit_out_prefix`;

    $z_score_feat_args .= " --nohit=$path_12_no_hit_z_out_tab";
}

if ($z_score_feat_args) {
    print "Generating .tab feature matrices...";
    $cmd = "Rscript $path_z_score_feature $z_score_feat_args --dir=$step12 > $path_12_z_out_tab_log";
    print("\n\t$cmd");
    `$cmd`;
    `mv $step12/Zscore_and_features_matrix.tab $step12/${lib_prefix}_Zscore_and_features_matrix.tab`
}


##### Renaming files folder 7

# ---- Post-step07 (Diamond): prefix outputs in $step6
{
    my @targets = qw(
        diamond_gt200_AllHits.log
        diamond_aligned.fasta
        diamond_gt200_AllHits_outfmt6.tab
        contigs_viral_BestHits_diamond.fasta
        contigs_nonviral_BestHits_diamond.fasta
        contigs_nohits_FINAL_diamond
        diamond_unaligned.fasta
        contigs_nohits_FINAL_diamond.fasta
        contigs_gt200_diamond_correct_strand.fasta
        diamond_aligned_linear.fasta
        diamond_gt200_AllHits_outfmt6_TAX.tab
        nonviral_AllHits_diamond.tab
        nonviral_BestHits_diamond.tab
        viral_AllHits_diamond.tab
        viral_BestHits_diamond.tab
    );

    for my $fname (@targets) {
        my $src = "$step7/$fname";
        next unless -e $src;
        next if $fname =~ /^\Q${lib_prefix}_\E/;
        my $dst = "$step7/${lib_prefix}_$fname";
        system("mv", "--", $src, $dst);
    }
}



# === POST-STEP07/12: conditional SAM->BAM conversions ===
{
    my $thr = defined($process) ? $process : 8;

    # 07/: somente quando -nohostfilter ativo
    if (defined $nohostfilter && $nohostfilter) {
        if (defined $step7 && -d $step7) {
            my $sam_07 = "$path_07_all_non_viral_sam_sort";
            if (-s $sam_07) {
                (my $bam_07 = $sam_07) =~ s/\.sam$/.bam/i;
                my $cmd = "samtools view -@ $thr -Sb '$sam_07' -o '$bam_07'";
                print "[STEP07->BAM] $cmd\n";
                my $rc = system($cmd);
                if ($rc == 0 && -s $bam_07) { unlink $sam_07 or warn "[WARN] $sam_07: $!\n"; }
                else { warn "[WARN] samtools view failed for $sam_07 (rc=$rc)\n"; }
            }
        }
    }

    # 11/: somente se -nononviralprofiles NÃO está ativo
    if (!(defined $nononviralprofiles && $nononviralprofiles)) {
        if (defined $step11 && -d $step11) {
            my $profiles_dir = "$path_11_profile_non_viral";
            if (-d $profiles_dir) {
                my @sams = glob("$profiles_dir/*.sam");
                if (@sams) {
                    print "[STEP11->BAM] converting ", scalar(@sams), " SAMs (threads=$thr)\n";
                    for my $sam (@sams) {
                        next unless -s $sam;
                        (my $bam = $sam) =~ s/\.sam$/.bam/i;
                        my $cmd = "samtools view -@ $thr -Sb '$sam' -o '$bam'";
                        print "[SAM->BAM] $cmd\n";
                        my $rc = system($cmd);
                        if ($rc == 0 && -s $bam) { unlink $sam or warn "[WARN] $sam: $!\n"; }
                        else { warn "[WARN] samtools view failed for $sam (rc=$rc)\n"; }
                    }
                }
            }
        }
    }
}


# === POST-STEP12: convert all SAMs in step12 to BAM ===
{
    my $thr = defined($process) ? $process : 8;
    if (defined $step12 && -d $step12) {
        my @sams = glob("$step12/*.sam");
        if (@sams) {
            print "[STEP12->BAM] converting ", scalar(@sams), " SAMs (threads=$thr)\n";
            for my $sam (@sams) {
                next unless -s $sam;
                (my $bam = $sam) =~ s/\.sam$/.bam/i;
                my $cmd = "samtools view -@ $thr -Sb '$sam' -o '$bam'";
                print "[SAM->BAM] $cmd\n";
                my $rc = system($cmd);
                if ($rc == 0 && -s $bam) { unlink $sam or warn "[WARN] $sam: $!\n"; }
                else { warn "[WARN] samtools view failed for $sam (rc=$rc)\n"; }
            }
        }
    }
}



# -----------------------------------------------------------------------

$current_time = Time::HiRes::gettimeofday();
$time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
$last_time = $current_time;

print STDOUT $time_msg;
print $time_msg;

# [CLEAN] Large SAMs consumed → remove (keep step 07/ directory)
for my $f ($path_07_all_non_viral_sam,
           $path_07_all_non_viral_sam_mapped,
           $path_07_all_viral_sam,
           $path_07_all_viral_sam_mapped,
           $path_07_dmnd_no_hits_sam,
           $path_07_dmnd_no_hits_sam_mapped) {
    if (defined($clean) && defined($f) && -e $f) {
        unlink $f or warn "[CLEAN] Could not remove $f: $!";
    }
}

#######################################################################
### Classifying virus × EVEs ------------------------------------------
#######################################################################

$step_name = "Classifying virus × EVEs";

$time_msg = getStepTimebBeginMsg($exec_id, $step_name);
print STDOUT $time_msg;
print $time_msg;

# -----------------------------------------------------------------------

my $path_13_eve_classif = "$step13/$exec_id-viral-eve.csv";

my $cmd_eve = "python3 $path_eve_classif --input $path_12_feat_matrix --output $path_13_eve_classif --classifier ".PATH_CLASSIF_EVE;

print "RUNING '$cmd_eve'...";
`$cmd_eve`;

# === DECLARE SUMMARY VARIABLES (STEP 13 cross classifications) ===
my ($viral_viral, $viral_eve, $nohit_viral);

# === STEP 13 SUMMARY (cross counts: origin vs classifier) ===
{
    $viral_viral  = "NA";
    $viral_eve    = "NA";
    $nohit_viral  = "NA";

    if (-e $path_13_eve_classif && -s $path_13_eve_classif) {
        chomp($viral_viral = `awk -F',' 'NR>1 && \$3=="viral" && \$NF=="viral" {c++} END{print c+0}' "$path_13_eve_classif" 2>/dev/null`);
        chomp($viral_eve   = `awk -F',' 'NR>1 && \$3=="viral" && \$NF=="eve"   {c++} END{print c+0}' "$path_13_eve_classif" 2>/dev/null`);
        chomp($nohit_viral = `awk -F',' 'NR>1 && \$3=="nohit" && \$NF=="viral" {c++} END{print c+0}' "$path_13_eve_classif" 2>/dev/null`);
    }

    print "[SUMMARY] Step13 -> viral_viral=$viral_viral\tviral_eve=$viral_eve\tnohit_viral=$nohit_viral\n";
}


# -----------------------------------------------------------------------

$current_time = Time::HiRes::gettimeofday();
$time_msg = getStepTimeEndMsg($exec_id, $step_name, $last_time, $current_time);
$last_time = $current_time;

print STDOUT $time_msg;
print $time_msg;


# === Filtering fasta Viral and EVE classification ===
my $viral_viral_fasta   = "$step13/${lib_prefix}_viral_viral.fasta";
my $viral_eve_fasta     = "$step13/${lib_prefix}_viral_eve.fasta";
my $unknown_viral_fasta = "$step13/${lib_prefix}_unknown_viral.fasta";

# === POST-STEP13: build ID sets and write FASTAs (viral/viral, viral/eve, nohit/viral) ===
 my (%viral_viral_ids, %viral_eve_ids, %unknown_viral_ids);  # nohit/viral -> "unknown_viral"
{
   

    # 1) Read classification CSV and collect IDs
    if (defined $path_13_eve_classif && -s $path_13_eve_classif) {
        open my $IN, "<", $path_13_eve_classif or warn "[WARN] Cannot open $path_13_eve_classif: $!\n";
        while (my $line = <$IN>) {
            chomp $line;
            next unless length $line;
            my @F = split /,/, $line, -1;             # CSV (no quoted fields assumed)
            my ($id, $sim, $class) = ($F[1], $F[2], $F[51]);  # col2, col3, col52 (1-based)
            next unless defined $id && length $id;

            $sim   = lc($sim  // '');
            $class = lc($class // '');

            if    ($sim eq 'viral' && $class eq 'viral') { $viral_viral_ids{$id}   = 1; }
            elsif ($sim eq 'viral' && $class eq 'eve')   { $viral_eve_ids{$id}     = 1; }
            elsif ($sim eq 'nohit' && $class eq 'viral') { $unknown_viral_ids{$id} = 1; }  # nohit/viral
        }
        close $IN;
    } else {
        warn "[WARN] Classification table missing or empty: $path_13_eve_classif\n";
    }

    # 2) Helper: extract by partial ID match on FASTA headers (linear FASTA)
    my $extract_fa = sub {
        my ($src, $dst, $ids_href) = @_;
        return 0 unless $src && -s $src;
        return 0 unless $dst;
        return 0 unless $ids_href && %{$ids_href};

        my $re = join('|', map { quotemeta($_) } keys %{$ids_href});
        return 0 unless length $re;

        open my $IN,  "<", $src or do { warn "[WARN] Cannot open $src: $!\n"; return 0; };
        open my $OUT, ">", $dst or do { warn "[WARN] Cannot write $dst: $!\n"; close $IN; return 0; };

        my ($keep, $n) = (0, 0);
        while (my $line = <$IN>) {
            if ($line =~ /^>/) {
                $keep = ($line =~ /$re/);
                $n++ if $keep;
                print $OUT $line if $keep;
            } else {
                print $OUT $line if $keep;
            }
        }
        close $IN; close $OUT;
        unlink $dst if $n == 0;  # avoid empty files
        return $n;
    };

    # 3) Write outputs:
    #    - viral_viral & viral_eve from $path_07_all_viral_fa
    #    - nohit/viral (unknown_viral) from $path_07_dmnd_no_hits_fa_FINAL
    my $n_vv = $extract_fa->($path_07_all_viral_fa,         $viral_viral_fasta,   \%viral_viral_ids);
    my $n_ve = $extract_fa->($path_07_all_viral_fa,         $viral_eve_fasta,     \%viral_eve_ids);
    my $n_uv = $extract_fa->($path_07_dmnd_no_hits_fa_FINAL,$unknown_viral_fasta, \%unknown_viral_ids);

    print "[EVE-SPLIT] $n_vv seqs -> $viral_viral_fasta\n"    if $n_vv;
    print "[EVE-SPLIT] $n_ve seqs -> $viral_eve_fasta\n"      if $n_ve;
    print "[EVE-SPLIT] $n_uv seqs -> $unknown_viral_fasta\n"  if $n_uv;
}


# === POST-STEP11: rename profile files by EVE classification ===
{
    for my $dir ($path_11_profile_viral, $path_11_profile_no_hits) {
        next unless defined $dir && -d $dir;
        opendir my $DH, $dir or do { warn "[WARN] Cannot open $dir: $!\n"; next; };

        while (my $f = readdir($DH)) {
            next if $f =~ /^\./;                 # skip . and ..
            my $src = "$dir/$f";
            next unless -f $src;
            next if $f =~ /^(viral_|eve_)/;      # skip if already renamed

            my $renamed = 0;

            if ($dir eq $path_11_profile_viral) {
                # inside smallrna_profiles_viral folder
                for my $id (keys %viral_viral_ids) {
                    if (index($f, $id) != -1) {
                        rename($src, "$dir/viral_$f");
                        $renamed = 1;
                        last;
                    }
                }
                next if $renamed;
                for my $id (keys %viral_eve_ids) {
                    if (index($f, $id) != -1) {
                        rename($src, "$dir/eve_$f");
                        $renamed = 1;
                        last;
                    }
                }
            }
            elsif ($dir eq $path_11_profile_no_hits) {
                # inside smallrna_profiles_no_hits folder
                for my $id (keys %unknown_viral_ids) {
                    if (index($f, $id) != -1) {
                        rename($src, "$dir/viral_$f");
                        $renamed = 1;
                        last;
                    }
                }
            }
        }
        closedir $DH;
    }
}

# === POST-STEP06/07: append viral/eve class to BLAST/DIAMOND tabs ===
{
    my @in_files = (
        "$step6/${lib_prefix}_viral_AllHits_blastn.tab",
        "$step6/${lib_prefix}_viral_BestHits_blastn.tab",
        "$step7/${lib_prefix}_viral_BestHits_diamond.tab",
        "$step7/${lib_prefix}_viral_AllHits_diamond.tab",
    );

    for my $in (@in_files) {
        next unless defined $in && -e $in && -s $in;

        my $out = "$in.class.tab";  # safe output
        open my $IN,  "<", $in  or do { warn "[WARN] Cannot open $in: $!\n"; next; };
        open my $OUT, ">", $out or do { warn "[WARN] Cannot write $out: $!\n"; close $IN; next; };

        my $header_done = 0;
        my $n = 0;
        while (my $line = <$IN>) {
            chomp $line;
            next unless length $line;

            # Header (first line that looks like column names)
            if (!$header_done && $line =~ /id/i && $line =~ /\t/) {
                print $OUT "$line\tclass\n";
                $header_done = 1;
                next;
            }

            my @F = split /\t/, $line, -1;
            my $id = $F[0] // '';
            my $cls = exists $viral_viral_ids{$id} ? 'viral_viral'
                    : exists $viral_eve_ids{$id}   ? 'viral_eve'
                    : '';
            print $OUT join("\t", @F, $cls), "\n";
            $n++;
        }
        close $IN;
        close $OUT;
        print "[CLASS] $n rows -> $out\n";
    }
}






# === FINAL SUMMARY TSV (end of script) ===
{
    # Output file path
    my $summary_tsv = (defined $step13 && -d $step13)
        ? "$step13/${lib_prefix}_summary.tsv"
        : "${lib_prefix}_summary.tsv";

    # Write header if file doesn't exist yet
    if (!-e $summary_tsv) {
        if (open my $H, ">", $summary_tsv) {
            print $H join("\t",
                "lib_prefix",
                "nreads_raw",
                "nreads_trimmed",
                "nreads_host",
                "nreads_bact",
                "nreads_filtered",
                "nreads_userrange",
                "nreads_20_23",
                "nreads_24_30",
                "ncontigs_gt200",
                "ncontigs_bn_viral",
                "ncontigs_bn_nonviral",
                "ncontigs_dmd_viral",
                "ncontigs_dmd_nonviral",
                "ncontigs_allviral",
                "ncontigs_allnonviral",
                "ncontigs_unknown",
                "nreads_viral",
                "nreads_nonviral",
                "nreads_unknown",
                "ncontigs_viralviral",
                "ncontigs_viral_eve",
                "ncontigs_nohit_viral"
            ), "\n";
            close $H;
        } else {
            warn "[WARN] Cannot create $summary_tsv ($!)\n";
        }
    }

    # Prepare values (use NA for missing)
    my @vals = (
        (defined $lib_prefix ? $lib_prefix : "LIB"),

        (defined $n_raw_reads_02           && $n_raw_reads_02 ne ""           ? $n_raw_reads_02           : "NA"),
        (defined $n_trimmed_reads_02       && $n_trimmed_reads_02 ne ""       ? $n_trimmed_reads_02       : "NA"),

        (defined $n_reads_host_03          && $n_reads_host_03 ne ""          ? $n_reads_host_03          : "NA"),

        (defined $n_reads_bacter_04        && $n_reads_bacter_04 ne ""        ? $n_reads_bacter_04        : "NA"),
        (defined $n_unmap_bac_04           && $n_unmap_bac_04 ne ""           ? $n_unmap_bac_04        : "NA"),
        (defined $n_unmap_filter_04        && $n_unmap_filter_04 ne ""        ? $n_unmap_filter_04        : "NA"),
        (defined $n_unmap_20_23_04         && $n_unmap_20_23_04 ne ""         ? $n_unmap_20_23_04         : "NA"),
        (defined $n_unmap_24_30_04         && $n_unmap_24_30_04 ne ""         ? $n_unmap_24_30_04         : "NA"),

        (defined $n_contigs_gt200_05       && $n_contigs_gt200_05 ne ""       ? $n_contigs_gt200_05       : "NA"),

        (defined $n_blastn_hits_virus      && $n_blastn_hits_virus ne ""      ? $n_blastn_hits_virus      : "NA"),
        (defined $n_blastn_hits_non_viral  && $n_blastn_hits_non_viral ne ""  ? $n_blastn_hits_non_viral  : "NA"),

        (defined $n_dmnd_hits_viral        && $n_dmnd_hits_viral ne ""        ? $n_dmnd_hits_viral        : "NA"),
        (defined $n_dmnd_hits_non_viral    && $n_dmnd_hits_non_viral ne ""    ? $n_dmnd_hits_non_viral    : "NA"),

        (defined $n_all_hits_viral         && $n_all_hits_viral ne ""         ? $n_all_hits_viral         : "NA"),
        (defined $n_all_hits_non_viral     && $n_all_hits_non_viral ne ""     ? $n_all_hits_non_viral     : "NA"),
        (defined $n_all_no_hits            && $n_all_no_hits ne ""            ? $n_all_no_hits            : "NA"),

        (defined $n_reads_viral_07         && $n_reads_viral_07 ne ""         ? $n_reads_viral_07         : "NA"),
        (defined $n_reads_non_viral_07     && $n_reads_non_viral_07 ne ""     ? $n_reads_non_viral_07     : "NA"),
        (defined $n_reads_no_hits_07       && $n_reads_no_hits_07 ne ""       ? $n_reads_no_hits_07       : "NA"),

        (defined $viral_viral              && $viral_viral ne ""              ? $viral_viral              : "NA"),
        (defined $viral_eve                && $viral_eve ne ""                ? $viral_eve                : "NA"),
        (defined $nohit_viral              && $nohit_viral ne ""              ? $nohit_viral              : "NA")
    );

    # Append the summary line
    if (open my $OUT, ">>", $summary_tsv) {
        print $OUT join("\t", @vals), "\n";
        close $OUT;
        print "[SUMMARY] Wrote final table line to $summary_tsv\n";
    } else {
        warn "[WARN] Cannot append to $summary_tsv ($!)\n";
    }
}




#######################################################################

# -- THE END --
finishSuccesfully();
