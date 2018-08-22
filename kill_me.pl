#!/usr/bin/perl
# kill_me
# Purpose: This scripts job is to kill processes owned by the user running this script
# on all compute nodes in the compute cluster this script is being run from.

# Dependencies
# This script most be run as root using sudo
# 2 symbolic links in /lib need to be added, pointing to 
# 	/apps/lava/1.0.3/linux2.6-glibc2.3-ia32e/lib/liblsfbat.so.1.0.0 to /lib/liblsfbat.so.1
# 	/apps/lava/1.0.3/linux2.6-glibc2.3-ia32e/lib/liblsf.so.1 and to /lib/liblsf.so.1

# Written By: Jon Swift 05/09
# Updated 10/09, Changed PATH to support LAVA
# Updated 03/10, added ping logic to UPTEST function
# Updated 4/10, Converted script to use ssh rather than rsh

use Shell;
use Sys::AlarmCall;
use lib "/apps/lava/1.0.3/linux2.6-glibc2.3-ia32e/lib/";
require 'getopts.pl';

chomp($HOST=`uname -n`);
$PROG="$0";
$PROG=~s/.*\/(.+)$/\1/;
$LOG="/tmp/${PROG}.log";
$LAVA_PATH="/apps/lava/1.0.3/linux2.6-glibc2.3-ia32e";
$ENV{"PATH"} = "/bin:/usr/bin:/sbin:/usr/sbin:$LAVA_PATH/bin";

# Add Gateway host names to $EXCLUDE
$EXCLUDE="node1001 node1002 node3001 node3001-1 node3002 node3002-1 node4001 node4002 node5001 node5002";

# Set $REAL_USER to the user who ran sudo to run this script
##############################################################################################
chomp($REAL_USER=`who am i`);
$REAL_USER=(split /\s/, $REAL_USER)[0];
chomp($EFECTIVE_USER=`whoami`);

# Confirm that $REAL_USER is not root
##############################################################################################
if ( "$REAL_USER" eq "root" )  {
	print "Error: $PROG can not be run as root\n";
	exit;

} else {

	# Set $COMMAND to the pkill command required
	$COMMAND="/usr/bin/pkill -9 -U $REAL_USER";
}

# Confirm that $EFECTIVE_USER is root
##############################################################################################
if ( "$EFECTIVE_USER" ne "root" ) {

	print "\nError: $PROG not being run by \sudo\", use \"sudo $PROG\"\n\n";
	exit;
}

# Confirm this script is run from a supported location, and set $CLUSTER based on $HOST
##############################################################################################
if ( $HOST =~ m/node1.../ ) {
	$CLUSTER="Hurricane";
	$NODE_REG="node1...";
} elsif ( $HOST =~ m/node3.../ ) {
     	$CLUSTER="Cyclone";
	$NODE_REG="node3...";
} elsif ( $HOST =~ m/node4.../ ) {
     	$CLUSTER="Twister";
	$NODE_REG="node4...";
} elsif ( $HOST =~ m/node5.../ ) {
     	$CLUSTER="Vortex";
	$NODE_REG="node5...";
} else {
	print "Error: $HOST is not part of one of the PWR compute clusters\n";
	print "$PROG must be run from a compute cluster development node or gateway\n";
	exit;
}

# The USAGE function is used to try to inform the user on how to use this script
##############################################################################################
sub USAGE {

print "\n***************************************************
  $PROG, is a tool to kill ALL proccess owned
  by \"$REAL_USER\" on select nodes of $CLUSTER.
  Development nodes and cluster gateways are 
  excluded by default.
***************************************************\n
  $PROG Usage:
  -a	All $CLUSTER nodes, including those currently running jobs as \"$REAL_USER\"
  -j	All $CLUSTER nodes except those running jobs as \"$REAL_USER\", as defined by bjobs
  -n	Only the $CLUSTER node(s) names listed here  (Can be used to include default exclude nodes)
  -n		-n node1 or -n \"node1 node2\"
  -x	Append $CLUSTER node(s) names listed here to exclude list. 
  -x	Also requires option a or j
  -ax		node1 or -x \"node1 node2\"
  -jx		node1 or -x \"node1 node2\"
  -d	Display excluded node names, nodes not subject to having processes killed   (Do Nothing)
  -h	Help,	Display this banner\n

***************************************************
  Primary Usage:
  sudo $PROG -j
***************************************************\n\n";
exit;
}

# The UPTEST function is used to determine if $NODE is up and working
##############################################################################################
sub UPTEST {
	
	# Set SYS to the 1 agrument to this function
	$SYS=$_[0];

	# define the variable PING the correct ping syntax
	$PING="/bin/ping -c2 -w1 $SYS | grep -c \'100% packet loss\' 1>/dev/null 2>&1";

	# Set PING_STATUS output of $PING
	$PING_STATUS=(system("/bin/sh -c \"$PING\""));

	if ( $PING_STATUS eq 0 ) {
		return 0;
	} else {

		# Open a file handle for the command rpcinfo -p, 
		# this will be used to make sure the node is up
		open (UPTEST,"rpcinfo -p $SYS|") or die "Unable to open the rpcinfo command $!\n";
	
		if (<UPTEST>) {
			return 1;
		} else {
			return 0;
		}
		close (UPTEST);
	}
		
}

# Function / wrapper for the ssh command
##############################################################################################
sub SSH {
   	system("ssh -q $_[0] $_[1] 2>/dev/null");
}

# Open the log file for writing
##############################################################################################
( -e $LOG ) and unlink $LOG;
open (LOG,">>$LOG")or die "Can not open the file $LOG $!\n";
system ("chmod 666 $LOG");
system("chown $REAL_USER $LOG");

# Use the standard subroutine Getopts to parse the arguments to this script
##############################################################################################
&Getopts("adjn:x:h") or &USAGE;

# Confirm syntax is valid
##############################################################################################
if ( $opt_a and $opt_j ) {
	print "\nError: Invalid syntax, option a and j are exclusive\n";
	&USAGE;
} elsif ( $opt_j and $opt_n ) {
	print "\nError: Invalid syntax, option j and n are exclusive\n";
	&USAGE;
} elsif ( $opt_a and $opt_n ) {
	print "\nError: Invalid syntax, option a and n are exclusive\n";
	&USAGE;
} elsif ( $opt_x and "$opt_a" eq "" and "$opt_j" eq "" )  {
	print "\nError: Invalid syntax, option x requires also using a or j\n";
	&USAGE;
}

# Display Usage banner
##############################################################################################
if ( $opt_h ) {
	&USAGE;
}

# Append development nodes for $CLUSTER to $EXCLUDE
##############################################################################################

# open the file handle NETGROUP using the command "ypcat -k netgroup  | grep devel_hosts | grep $NODE_REG
open (NETGROUP,"ypcat -k netgroup | grep devel_hosts | grep $NODE_REG|") or die "Unable to open the ypcat -k netgroup command, $!\n";

LOOP: foreach $DEVEL_NODE (split /\s/,<NETGROUP>) {

	# Remove any end of line char
	chomp($DEVEL_NODE);

	# Skip any entry that does not match node*
	( $DEVEL_NODE !~ m/$NODE_REG/i ) and next LOOP;

	# Skip any entry that contains pwrutc.com
	( $DEVEL_NODE =~ m/pwrutc\.com/i ) and next LOOP;

	# Remove the following from each line, ( ) , - therock
	$DEVEL_NODE=~s/\(//g;
	$DEVEL_NODE=~s/\)//g;
	$DEVEL_NODE=~s/\,//g;
	$DEVEL_NODE=~s/-therock//g;
	$DEVEL_NODE=~s/-hurricane//g;

    	# If $DEVEL_NODE has NOT already been added to $EXCLUDE, add it
	foreach $EXCLUDE_NODE (split /\s/, $EXCLUDE) {

		if ( "$EXCLUDE_NODE" eq "$DEVEL_NODE" ) { 
			next LOOP;
		}
	}

	# Add $DEVEL_NODE to $EXCLUDE
        $EXCLUDE="$EXCLUDE $DEVEL_NODE"
}
close(NETGROUP);

# This section adds nodes to supplied to @NODES
##############################################################################################
if ( $opt_n ) {

	# Go through each node name and confirm it is a valid node name
	foreach $INCLUDE_NODE (split /\s/, $opt_n ) {

		# Set VALID_NODE to NO
		$VALID_NODE="NO";

		# open the file handle NODES using the ypcat hosts command
		open (NODES,"ypcat -t hosts.byaddr | grep $NODE_REG|") or die "Unable to open the NIS host file, $!\n";

		LOOP: foreach $NODE (<NODES>) {

			# Set $NODE to the 2nd field in the host file
			$NODE=(split /\s+/, $NODE)[1];
	
        		# Set VALID_NODE to YES if $NODE matches one of the exclude nodes
			if ( "$NODE" eq "$INCLUDE_NODE" ) { 
				$VALID_NODE="YES";
				last LOOP;
			}
		}
	
        	# If VALID_NODE is a null it means that $NODE is invalid
        	if ( "$VALID_NODE" eq "NO" ) {
               		print "\nThe node name $INCLUDE_NODE is not valid\n\n";
               		print LOG "\nThe node name $INCLUDE_NODE is not valid\n\n";
               		exit 0;
        	}
	
    		# Add $INCLUDE_NODE to @NODES
        	push (@NODES, $INCLUDE_NODE);

		close (NODES);
	}

	# Set the SYNTAX flag
 	$SYNTAX="OK";

	# Set KILL_NODES
	$KILL_NODES="@NODES";
}

# Add nodes names from $EXCLUDE to @EXCLUDE that match $NODE_REG
##############################################################################################
LOOP: foreach $EXCLUDE_NODE (split /\s/, $EXCLUDE) {

	# Skip $EXCLUDE_NODE that does not matches $$NODE_REG
	( $EXCLUDE_NODE !~ m/$NODE_REG/ ) and next LOOP;		

	# Confirm $EXCLUDE_NODE is not contained in @NODES
	if ( @NODES ) {
		foreach $INCLUDE_NODE (@NODES) {

			# Skip $EXCLUDE_NODE if it matches $INCLUDE_NODE
			if ( "$EXCLUDE_NODE" eq "$INCLUDE_NODE" ) {
				next LOOP;		
			}
		}
	}

	# Add any $EXCLUDE_NODE that matches $NODE_REG to @EXCLUDE
	( $EXCLUDE_NODE =~ m/$NODE_REG/) and push (@EXCLUDE, $EXCLUDE_NODE);
}

# Add nodes names running jobs as $REAL_USER to the array @EXCLUDE
##############################################################################################
if ( $opt_j ) {

	# Confirm required LSF/Java library links exists, create as needed
	if ( -l "/lib/liblsf.so.1" ) {
		#print "/lib/liblsf.so.1 link exists\n";
	} else {
		system("ln -s $LAVA_PATH/lib/liblsf.so.1 /lib/liblsf.so.1");
	}
	if ( -l "/lib/liblsfbat.so.1" ) {
		#print "/lib/liblsfbat.so.1 link exists\n";
	} else {
		system("ln -s $LAVA_PATH/lib/liblsfbat.so.1.0.0 /lib/liblsfbat.so.1");
	}

	# open the file handle BJOBS using the bjobs -u $REAL_USER command
	open (BJOBS,"bjobs -u $REAL_USER 2>/dev/null|") or die "Unable to open the bjobs command, $!\n";

	# Based on if jobs are running as $REAL_USER, add nodes running jobs to @EXCLUDE
	if (<BJOBS>) {

		# Go through each node name and confirm it is a valid node name
		LOOP: foreach $EXCLUDE_NODE (<BJOBS>) {

			# Remove any end of line char
			chomp($EXCLUDE_NODE);
	
			# Skip lines that start with JOBID
			( $EXCLUDE_NODE =~ m/^JOBID/ ) and next LOOP;
	
			# Skip lines that conatin the key word PEND
			( $EXCLUDE_NODE =~ m/PEND/ ) and next LOOP;
	
			# Change $EXCLUDE_NODE from something like ione of the following lines
			# OBID   USER    STAT  QUEUE      FROM_HOST   EXEC_HOST   JOB_NAME   SUBMIT_TIME
			# 94308  edlynch RUN   pc_twister node4105    2*node4130  rs68full   Apr 29 15:21
                	#                            2*node4227
                	#                            2*node4230
			#                              node4231
			# to node4130 or node4227 or node4230

			# Convert $REAL_USER to a 7 digit ID, required because bjobs truncates the ID
			$REAL_USER=~s/(.......).*/\1/;

			if ( $EXCLUDE_NODE =~ m/$REAL_USER/ ) {
				$EXCLUDE_NODE=~s/^\d+.*(\d*\**$NODE_REG)\s.*/\1/;
			} else {
				$EXCLUDE_NODE=~s/\s//g;
			}
	
			# Remove the NUM* from 2*node4227
			$EXCLUDE_NODE=~s/[1-9]\*(node....)/\1/;
		
			# Confirm $EXCLUDE_NODE is set properly
			if ( $EXCLUDE_NODE !~ m/^$NODE_REG/ ) {
				print "Error: The required variable \"EXCLUDE_NODE\" not set properly\n";
				print LOG "Error: The required variable \"EXCLUDE_NODE\" not set properly\n";
				exit;
			}
	
    			# If $EXCLUDE_NODE has NOT already been added to @EXCLUDE, add it
			$EXCLUDE="NO";
			LOOP: foreach $NODE (@EXCLUDE) {
	
				if ( "$NODE" eq "$EXCLUDE_NODE" ) { 
					$EXCLUDE="YES";
					next LOOP;
				}
			}
	
			# Add $EXCLUDE_NODE to @EXCLUDE
        		push (@EXCLUDE, $EXCLUDE_NODE);
		}

	} else {
		print "\nNote: No Jobs running as \"$REAL_USER\" on $CLUSTER,\n";
		print "no additional nodes excluded.\n\n";
	}
	close (BJOBS);

	# Set the SYNTAX flag
 	$SYNTAX="OK";

	# Set $opt_a to a to create @NODES
	$opt_a="a";

	# Set KILL_NODES
	$KILL_NODES="All Nodes, except those running jobs";
}

# This section adds nodes to exclude provided on the command line to the array @EXCLUDE
##############################################################################################
if ( $opt_x ) {

	# Go through each node name and confirm it is a valid node name
	foreach $EXCLUDE_NODE (split /\s/, $opt_x ) {

		# Set VALID_NODE to NO
		$VALID_NODE="NO";

		# open the file handle NODES using the ypcat hosts command
		open (NODES,"ypcat -t hosts.byaddr| grep $NODE_REG|") or die "Unable to open the NIS host file, $!\n";

		LOOP: foreach $NODE (<NODES>) {

			# Set $NODE to the 2nd field in the host file
			$NODE=(split /\s+/, $NODE)[1];
	
        		# Set VALID_NODE to YES if $NODE matches one of the exclude nodes
			if ( "$NODE" eq "$EXCLUDE_NODE" ) { 
				$VALID_NODE="YES";
				last LOOP;
			}
		}
	
        	# If VALID_NODE is a null it means that $NODE is invalid
        	if ( "$VALID_NODE" eq "NO" ) {
               		print "\nThe node name $EXCLUDE_NODE is not valid\n\n";
               		print LOG "\nThe node name $EXCLUDE_NODE is not valid\n\n";
               		exit 0;
        	}
	
    		# Add $EXCLUDE_NODE to @EXCLUDE
        	push (@EXCLUDE, $EXCLUDE_NODE);

		close (NODES);
	}

	# Set the SYNTAX flag
 	$SYNTAX="OK";
}

# Display default node names excluded from host name kill list
##############################################################################################
if ( $opt_d ) {
	print "\nExcluded $CLUSTER node names\n";
	foreach $EXCLUDE_NODE (@EXCLUDE) {
		print "$EXCLUDE_NODE ";
	}
	print "\n";
	exit;
}

# Add all the host names in this cluster to the array @NODES
##############################################################################################
if ( $opt_a ) {

	# open the file handle NODES using the ypcat hosts command
	open (NODES,"ypcat -t hosts.byaddr| grep $NODE_REG|") or die "Unable to open the NIS host file, $!\n";

	LOOP: foreach $NODE (<NODES>) {

		# Set $NODE to the 2nd field in the host file
		$NODE=(split /\s+/, $NODE)[1];

 		# Skip node namess that do not match nodeNNNN
		( "$NODE" !~ m/node[1-9][0-9]+/ ) and next LOOP;

		# Skip any Nodes that are in a different cluster
		( "$NODE" !~ m/$NODE_REG/ ) and next LOOP;

		# Skip this node
		( "$NODE" eq "$HOST" ) and next LOOP;

    		# Add $NODE to @NODES
        	push (@NODES, $NODE);
	}

	close (NODES);

	# Set the SYNTAX flag
 	$SYNTAX="OK";

	# Set KILL_NODES as needed
	( "$KILL_NODES" eq "" ) and $KILL_NODES="All Nodes";
}

# Make sure the command syntax used is correct
##############################################################################################
( "$SYNTAX" ne "OK" ) and &USAGE;

# Confirm action
##############################################################################################

# Ask the question, should we proceed
print "\nKill all processes owned by $REAL_USER on $KILL_NODES Y/N > ";

# Proccess answer
while (<STDIN>) {

	# Remove EOL character
	chomp $_;

	# No Answer, just hit return
	if ( "$_" eq "" ) {
		print "\nKill all processes owned by $REAL_USER on $KILL_NODES Y/N > ";

	# Negative answer
	} elsif ( $_ =~ m/N/i or $_ =~ m/NO/i or $_ =~ m/Q/i )  {
		exit;

	# Invalid answer
	} elsif ( $_ !~ m/Y/i or $_ =~ m/YES/i )  {
		print "\nInvalid responce, $_\n";
		print "\nKill all processes owned by $REAL_USER on $KILL_NODES Y/N > ";

	# Everything else, Positive answer
	} else {
		close(STDIN);
		print "\nKilling all processes owned by $REAL_USER on $KILL_NODES\n\n";
		print LOG "\nKilling all processes owned by $REAL_USER on $KILL_NODES\n\n";
	}
}

# kill all process owned by $REAL_USER on all nodes in @NODES expect the nodes listed in @EXCLUDE
##############################################################################################
LOOP: foreach $NODE (@NODES) {

	# Skip over any of the exclude nodes listed in @EXCLUDE
	foreach $EXCLUDE_NODE (@EXCLUDE) {

        	if ($EXCLUDE_NODE eq $NODE) {
                	print "Skipping $EXCLUDE_NODE\n";
                	next LOOP;
        	}
	}

	# Confirm $NODE is up an working
	$UPTEST=alarm_call(2,'&UPTEST',$NODE);

	if ( $UPTEST == 1 ) {

		print "$PROG killing all $REAL_USER processes on $NODE\n";
		print LOG "$PROG killing all $REAL_USER processes on $NODE\n";

		# Set RESULT to TIMEOUT if SSH fails
		# alarm_call is a function to force a timeout of ssh
		# on systems that it (ssh) hangs
		$RESULT=alarm_call(15,'&SSH',$NODE,$COMMAND);

		# if $RESULT is set to TIMEOUT, that means that the ssh process has failed
		if ( "$RESULT" eq "TIMEOUT" ) { 
			print "Problem with $NODE, pingable, but can not ssh to it\n";
			print LOG  "Problem with $NODE, pingable, but can not ssh to it\n";
		}

	 } else {
         	print "\n$NODE is down\n";
 	}
}

# Print Banner displying log file name
##############################################################################################
print "\n\n##################################################\n";
printf"%-5s %-3s %-3s %-4s %-2s %-26s %-1s\n","#","The","log","file","is","$LOG","#";
print "##################################################\n\n\n";
