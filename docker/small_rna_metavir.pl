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
# TODO: 2024-01-18 - Add suport for chosing among development or production container version
# 

use constant RUNTIME_DOCKER => "docker";
# use constant RUNTIME_PODMAN => "podman";

# use constant IMG_NAME => "small_rna_metavir";
use constant IMG_NAME => "small_rna_metavir_dev";
use constant IMG_TAG =>  "latest";
# use constant CONTAINER_TARGET => "_";
use constant CONTAINER_NAME => "small_rna_metavir";

use constant PATH_LOG_MAIN => "./small_rna_metavir.log";
use constant PATH_DOCKERFILE =>  ".";
# use constant PATH_DOCKERFILE =>  "invalid/path";

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
}

# ===========================================================================
# ---  Set container runtime ------------------------------------------------
# ===========================================================================

my $runtime = "";

logMessage("Checking if Docker is available...");

if (execCommand("command -v docker 2>/dev/null") && execCommand("docker run hello-world 2>/dev/null")) {
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

# Build image
logMessage("Checking if image '$imgNameAndTag' exists...");

if (not execCommand("$runtime image inspect \"$imgNameAndTag\"")) {
    
    logMessage("Image '$imgNameAndTag' doesn't exist. Trying to build it now...");

    if (execCommand("$runtime build -t $imgNameAndTag ".PATH_DOCKERFILE)) {
        logMessage("Image '$imgNameAndTag' successfully built");
    } else {
        printErrorAndDie("Failure on trying to build image '$imgNameAndTag'");
    }
}

logMessage("Image '$imgNameAndTag' exists.");

# Run container
logMessage("Checking if container '".CONTAINER_NAME."' is running...");

if (not execCommand("$runtime ps | grep ".CONTAINER_NAME)) {
    
    my $hasError = 0;
    logMessage("Container '".CONTAINER_NAME."' isn't running. Checking if it exists...");

    # Create container if it doesn't exist
    if (not execCommand("$runtime ps -a | grep ".CONTAINER_NAME)) {
        
        logMessage("Container '".CONTAINER_NAME."' doesn't exist. We're creating it now...");
        
        if (not execCommand("$runtime run -d -t --name ".CONTAINER_NAME." $imgNameAndTag")) {
            $hasError = 1;
        }

    # Restart container if it already exists
    } else {
        
        logMessage("Container '".CONTAINER_NAME."' already exist. We're restarting it now...");
        
        if (not execCommand("$runtime start ".CONTAINER_NAME)) {
            $hasError = 1;
        }
    }

    if ($hasError) {
        printErrorAndDie("Failure as trying to start container '".CONTAINER_NAME."'");
    }
}

logMessage("Container '".CONTAINER_NAME."' is running...");

# ===========================================================================
# --- Run pipeline over libraries -------------------------------------------
# ===========================================================================