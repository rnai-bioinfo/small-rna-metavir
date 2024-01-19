use strict;
use warnings;

# use Time::HiRes;
# use POSIX qw(strftime);
# use Getopt::Long;

# 
# TODO: 2023-12-09 - Make it work with podman
# TODO: 2023-12-09 - Arg "prefered runtime"
# TODO: 2023-12-09 - Arg "config file path"
# TODO: 2023-12-09 - Rethink about this script location
# TODO: 2023-12-09 - Rethink about make the container to keep running
# TODO: 2024-01-18 - Measure execution time
# TODO: 2024-01-18 - Generate a new log file for each execution
# 

use constant RUNTIME_DOCKER => "docker";
# use constant RUNTIME_PODMAN => "podman";

# use constant IMG_NAME => "small_rna_metavir";
use constant IMG_NAME => "small_rna_metavir_dev";
use constant IMG_TAG =>  "latest";
use constant CONTAINER_NAME => "small_rna_metavir";

use constant PATH_LOG_MAIN => "./small_rna_metavir.log";
use constant PATH_DOCKERFILE =>  ".";
# use constant PATH_DOCKERFILE =>  "invalid/path";

# 
# TODO: 2024-01-18 - Place it some place better
# 
# ERROR POLICY
# 0 => Fail on error
# 1 => Do not fail & return empty
# 2 => Ignore error & return command output
use constant ERR_POLICE_FAIL => 0;
use constant ERR_POLICE_RETURN_EMPTY => 1;
# use constant ERR_POLICE_RETURN_ERR => 2;

# ===========================================================================
# --- Set up logging files --------------------------------------------------
# ===========================================================================

my $LOG_MAIN_FH;

# open($LOG_MAIN_FH, ">>", PATH_LOG_MAIN) or die "Couldn't open log file: $!"; # $! is a special variable holding the error
open($LOG_MAIN_FH, ">", PATH_LOG_MAIN) or die "Couldn't open log file: $!"; # $! is a special variable holding the error

# *STDERR = $LOG_ERR_FH;
# select $LOG_MAIN_FH;

# ===========================================================================
# --- Parse input -----------------------------------------------------------
# ===========================================================================

# 
# TODO: 2024-01-18 - Read user defined parameters
# 

# ===========================================================================
# TODO: ADD Description -------------------------------------------------
# ===========================================================================

sub logMessage {
    
    my $msg = $_[0];
    $msg = "[info] $msg\n";
    
    print $LOG_MAIN_FH $msg;
    print STDOUT $msg;
}

sub printErrorAndDie {
    
    my $msg = $_[0] // "Program finished unexpectadly";
    $msg = "\n[ERROR] $msg\n";

    print $LOG_MAIN_FH $msg;
    print STDERR $msg;
    print STDOUT "Check '".PATH_LOG_MAIN."' for details\n";
    
    exit 1;
}

sub execCommand {
    # 
    # TODO: 2024-01-12 - ADD Description
    # 
    my $cmd = $_[0];
    my $errorPolice = $_[1] // ERR_POLICE_FAIL;

    print $LOG_MAIN_FH "[command] $cmd\n";
    print STDOUT "[command] $cmd\n";
    
    # $cmd = "$cmd 2> ".PATH_LOG_MAIN;
    
    open my $pipe, "$cmd 2>&1 |" or die "Failed to execute command: $!\n"; # Redirect STDERR into STDOUT
    my $output = ""; # `$cmd`;
    
    while (<$pipe>) {
        $output .= $_;
        print $LOG_MAIN_FH $_;
        print STDOUT $_;
    }

    close $pipe;

    # '$?' has the 16bits exit status of the last command (8 for the actual status + 8 for aditional info).
    # So we bitwise shift this value to the right to get the actual staus value (hopefully 0)
    my $exitStatus = $? >> 8;

    # print STDOUT ">>> \$exitStatus == $exitStatus >>><<< \$output == $output \n\n";
    # print $LOG_MAIN_FH ">>> \$exitStatus == $exitStatus >>><<< \$output == $output \n\n";

    !$exitStatus && return $output;
    $errorPolice == ERR_POLICE_RETURN_EMPTY && return;
    printErrorAndDie();
}

# ===========================================================================
# ---  Set container runtime ------------------------------------------------
# ===========================================================================

my $runtime = "";

logMessage("Checking if Docker is available...");

if (execCommand("command -v docker 2>/dev/null", ERR_POLICE_RETURN_EMPTY)
    && execCommand("docker run hello-world 2>/dev/null", ERR_POLICE_RETURN_EMPTY)
) {
    $runtime = RUNTIME_DOCKER;
} else {
    logMessage("Docker doesn't seem to be available.");
}

if (!$runtime) {
    printErrorAndDie("You need a container runtime but neither Docker nor podman could be found");
}

logMessage("Using $runtime runtime...");

# ===========================================================================
# --- Set running container up ----------------------------------------------
# ===========================================================================

my $imgNameAndTag = IMG_NAME.":".IMG_TAG;
my $command = "";

# Build image
# $command = "$runtime images $imgNameAndTag";
$command = "$runtime image inspect \"$imgNameAndTag\"";

if (not execCommand($command, ERR_POLICE_RETURN_EMPTY)) {
    
    logMessage("Image '$imgNameAndTag' doesn't exist. Trying to build it now...");

    $command = "$runtime build -t $imgNameAndTag ".PATH_DOCKERFILE;
    if (execCommand($command, ERR_POLICE_FAIL)) {
        logMessage("Image '$imgNameAndTag' successfully built");
    } else {
        printErrorAndDie("Failure on trying to build image '$imgNameAndTag'");
    }
}

# # printErrorAndDie("This is a test...");
# # exit 0;

# # Run container
# $command = "$runtime ps -f \"name=".CONTAINER_NAME."\" | grep -q \"".CONTAINER_NAME."\"";

# if (not execCommand($command)) {
    
#     logMessage("Container '".CONTAINER_NAME."' isn't running. we're starting it now...");

#     $command = "$runtime run -d -t --name ".CONTAINER_NAME." $imgNameAndTag &> /dev/null";
#     if (execCommand($command)) {
#         logMessage("Container '".CONTAINER_NAME."' successfully started");
#     } else {
#         printErrorAndDie("Failure on trying to start ontainer '".CONTAINER_NAME."'");
#     }
# }

# ===========================================================================
# --- Run pipeline over libraries -------------------------------------------
# ===========================================================================