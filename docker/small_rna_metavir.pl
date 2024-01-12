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
    
    print $LOG_MAIN_FH "[info] $msg";
    $is_verbose && print STDOUT $msg."\n";
}

sub printErrorAndDie {
    
    my $msg = $_[0] // "Program finished unexpectadly";
    $msg = "[ERROR] $msg";

    print $LOG_MAIN_FH $msg."\n";
    print STDERR $msg."\n";
    print STDOUT $msg;
    print STDOUT "\nCheck '".PATH_LOG_ERR."' for details\n";
    
    exit 1;
}

sub execCommand {
    # 
    # TODO: 2024-01-12 - ADD Description
    # 

    my $cmd = $_[0];
    print $LOG_MAIN_FH "[cmd] $cmd\n";
    
    $cmd = "$cmd 2> ".PATH_LOG_ERR;
    # my $exitStatus = system($cmd);
    my $output = `$cmd`;

    # '$?' has the 16bits exit status of the last command (8 for the actual status + 8 for aditional info).
    # So we bitwise shift this value right to stay get the actual staus value (hopefully 0)
    my $exit_status = $? >> 8;
    $exit_status && printErrorAndDie();

    return $output;
}

# ===========================================================================
# ---  Set container runtime ------------------------------------------------
# ===========================================================================

my $runtime = "";

# if (execCommand("command -v docker 2>/dev/null") && execCommand("docker run hello-world 2>/dev/null")) {
if (execCommand("docker image inspect some_docker_image") && execCommand("docker run hello-world 2>/dev/null")) {
    $runtime = RUNTIME_DOCKER;
} else {
    printErrorAndDie("You need a container runtime but neither Docker nor podman could be found");
}

logMessage("Using $runtime runtime...");

# ===========================================================================
# --- Set running container up ----------------------------------------------
# ===========================================================================

my $imgNameAndTag = IMG_NAME.":".IMG_TAG;
my $command = "";

# Build image
$command = "$runtime image inspect \"$imgNameAndTag\"";

if (not execCommand($command)) {
    
    logMessage("Image '$imgNameAndTag' doesn't exist. We're building it now");

    $command = "$runtime build -t $imgNameAndTag ".PATH_DOCKERFILE;
    if (execCommand($command)) {
        logMessage("Image '$imgNameAndTag' successfully built");
    } else {
        printErrorAndDie("Failure on trying to build image '$imgNameAndTag'");
    }
}

# printErrorAndDie("This is a test...");
# exit 0;

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