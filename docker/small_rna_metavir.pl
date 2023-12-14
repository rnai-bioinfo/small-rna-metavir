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
# TODO: 2023-12-09 - Redirect errors / warnings into a log file
# 

use constant RUNTIME_DOCKER => "docker";
# use constant RUNTIME_PODMAN => "podman";

# use constant IMG_NAME => "small_rna_metavir";
use constant IMG_NAME => "small_rna_metavir_dev";
use constant IMG_TAG =>  "latest";
use constant CONTAINER_NAME => "small_rna_metavir";

use constant PATH_LOG_MAIN => "./small_rna_metavir.log";
use constant PATH_LOG_ERR => "./small_rna_metavir.err.log";
use constant PATH_DOCKERFILE =>  ".";

# ===========================================================================
# --- Set up logging files --------------------------------------------------
# ===========================================================================

my $LOG_MAIN_FH;
my $LOG_ERR_FH;

open($LOG_MAIN_FH, ">>", PATH_LOG_MAIN) or die "Couldn't open: $!"; # $! is a special variable holding the error
open($LOG_ERR_FH, ">>", PATH_LOG_ERR) or die "Couldn't open: $!"; # $! is a special variable holding the error

*STDERR = $LOG_ERR_FH;
select $LOG_MAIN_FH;

# ===========================================================================
# --- Parse input -----------------------------------------------------------
# ===========================================================================

my $is_verbose = 1;

# ===========================================================================
# TODO: ADD Description -------------------------------------------------
# ===========================================================================

sub logMessage {
    
    my $msg = $_[0];
    $msg = "$msg\n";
    
    print $LOG_MAIN_FH $msg;
    
    if ($is_verbose) {
        print STDOUT $msg;
    }
}

sub printErrorAndDie {
    
    my $msg = $_[0] or die "Program fineshed unexpectadly";
    $msg = "[ERROR] $msg";

    print $LOG_MAIN_FH $msg;
    print STDERR $msg;
    
    print STDOUT $msg;
    print STDOUT "Check '".PATH_LOG_ERR."' for details\n";
    exit 1;
}

sub execCommand {
    my $cmd = $_[0];
    print $LOG_MAIN_FH "[cmd] $cmd\n";
    return `$cmd`;
}

# ===========================================================================
# ---  Set container runtime ------------------------------------------------
# ===========================================================================

my $runtime = "";
# if (`command -v docker 2>/dev/null` and `docker run hello-world 2>/dev/null`) {
if (execCommand("command -v docker 2>/dev/null") && execCommand("docker run hello-world 2>/dev/null")) {
    $runtime = RUNTIME_DOCKER;
} else {
    printErrorAndDie("You need a container runtime but neither Docker nor podman could be found");
}

logMessage("Using $runtime runtime...\n");

# ===========================================================================
# --- Set running container up ----------------------------------------------
# ===========================================================================

my $imgNameAndTag = IMG_NAME.":".IMG_TAG;
my $command = "";

# Build image
# $command = "$runtime image inspect \"$imgNameAndTag\" &> /dev/null";
$command = "$runtime image inspect \"$imgNameAndTag\"";

if (not execCommand($command)) {
    
    logMessage("Image '$imgNameAndTag' doesn't exist. We're building it now");

    $command = "$runtime build -t $imgNameAndTag ".PATH_DOCKERFILE;
    if (execCommand($command)) {
        logMessage("Image '$imgNameAndTag' successfully build");
    } else {
        printErrorAndDie("Failure on trying to build image '$imgNameAndTag'");
    }
}

# Run container
$command = "$runtime ps -f \"name=".CONTAINER_NAME."\" | grep -q \"".CONTAINER_NAME."\"";

if (not execCommand($command)) {
    
    logMessage("Container '".CONTAINER_NAME."' isn't running. we're starting it now...");

    $command = "$runtime run -d -t --name ".CONTAINER_NAME." $imgNameAndTag &> /dev/null";
    if (execCommand($command)) {
        logMessage("Container '".CONTAINER_NAME."' successfully started");
    } else {
        printErrorAndDie("Failure on trying to start ontainer '".CONTAINER_NAME."'");
    }
}

# ===========================================================================
# --- Run pipeline over libraries -------------------------------------------
# ===========================================================================