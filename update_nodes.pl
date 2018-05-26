#!/usr/bin/perl

# update_nodes
# Purpose: This scripts job is to update the other nodes on the PC/Linux cluster. It
# does this by doing one of 3 different things. Either separately or all 3 different
# tasks at the same time. Task 1 can be used to update or install a single file on 
# each of the other nodes. Task 2 can be used to update or install an entire directory 
# and any subdirectories on each of the other nodes. Both of this tasks use rdist to
# update or install the data. Task 3 can be used to execute the same command on each 
# of the other nodes.

# Written By Jon Swift 10-00
# Updated 01-01, Added the Alarm Sytsem function, used to monitor rsh
# Updated 04-01, Added logic to prevent this script from writing to node1000 
# Updated 01-03, Added logic to restrict the host/node names to 001 through node1999
# Updated 02-04, Added logic to change the  host/node names to 3001 through node3999
# Updated 12-04, Added logic to change the  host/node names to 4001 through node4999
# Updated 08-07, Added the -t option, -t is used to define the rsh timout value
# Updated 06-08, added full path to any system command being used, required to run non-interactively
# Updated 04-10, Updated script to use ssh rather than rsh


use Shell;
use Sys::AlarmCall;
require 'getopts.pl';
chomp ($NODE=`uname -n`);
chomp ($OS=`uname -s`);
chomp ($User=`whoami`);
chomp ($0=`basename $0`);
$TIMEOUT="10";
$LOG="/tmp/$0.log";

# Set EXCLUDE1 to the directory names we do not want modified/touched
@EXCLUDE1=qw(/ /etc /usr /dev /proc /var /opt);

# Set EXCLUDE2 to the directory names we do not want to have the directory 
# or any of it subdirectories modified/touched
@EXCLUDE2=qw(/apps /scratch /home);

# Usage subroutine
sub USAGE {
	print "\n$0 Usage: 
	-c command 
	-c uname or -c \"ls -la\" or -c \"ls -la \; uname -a\"
	-d directory-name
	-d /etc/rc.d/init.d or -d \"/etc/rc.d/init.d /etc/sys/init\"
	-e exclude node
	-e node1 or -e \"node1 node2\" or \"node43..\"	
	-f file-name
	-f /etc/fstab or -f \"/etc/fstab /etc/lsf.conf\"
	-i include only node(s)
	-i node41.., include only nodes node41xx nodes
	-t ssh timout value in seconds, default = 10 seconds
	-t 120, This sets the ssh time out value to 120 seconds\n\n";
	exit 0;
}

# Function / wrapper for the ssh command
sub SSH {
        $HOST=$_[0];
	$COMMAND=$_[1];
        system("/usr/bin/ssh -q $HOST $COMMAND 2>/dev/null | tee -a $LOG");
}

# Make sure this script is only being used on the Linux PC cluster
if ( "${OS}" ne "Linux" or "${NODE}" !~ m/node4[0-9]+/ ) {
	print "\n${0} must executed on the Linux Twister cluster\n";
	exit 1;
}

# Make sure this script is only being run as root
if ( "$User" ne "root" ) {
	print "\n${0} must executed as root\n";
	exit 1;
}

# Function for the signal catcher
sub SIGNAL_INT {
	sleep 1;
	print "\nExiting $0\n\n";
	exit 0;
}

# If the user hits Ctrl C (^C), trap it and execute SIGNAL_INT
$SIG{'INT'} = 'SIGNAL_INT';

# Use the standard subroutine Getopts to parse the arguments to this script
&Getopts("c:d:e:f:i:t:") or &USAGE;

# This section checks to make sure the node name(s) supplied
if ( $opt_i ) {

	# Set the SYNTAX flag
	$SYNTAX="OK";

	# Go through each node name and confirm it is a valid node name
	foreach $NODE (split /\s/, $opt_i ) {

		if ( $NODE =~ m/\.*/ ) {

			# Add $NODE to @INCLUDE
			push (@INCLUDE, $NODE);
	
		} else {
	
			# Set VALID_NODE
			chomp ($VALID_NODE=`ypmatch $NODE hosts 2>/dev/null`);
			
			# If VALID_NODE is a null it means that $NODE is invalid
			if ( "$VALID_NODE" eq "" ) {
				print "\nThe node name $NODE is not valid\n\n";
				exit 0;
			}
		
			# Add $NODE to @INCLUDE
			push (@INCLUDE, $NODE);
		}
	}
}
	
# This section checks to make sure the node name(s) supplied
if ( $opt_e ) {

	# Set the SYNTAX flag
	$SYNTAX="OK";

	# Go through each node name and confirm it is a valid node name
	foreach $NODE (split /\s/, $opt_e ) {

		if ( $NODE =~ m/\.*/ ) {

			# Add $NODE to @EXCLUDE
			push (@EXCLUDE, $NODE);
		} else {

			# Set VALID_NODE
			chomp ($VALID_NODE=`ypmatch $NODE hosts 2>/dev/null`);
	
			# If VALID_NODE is a null it means that $NODE is invalid
			if ( "$VALID_NODE" eq "" ) {
				print "\nThe node name $NODE is not valid\n\n";
				exit 0;
			}
	
			# Add $NODE to @EXCLUDE
			push (@EXCLUDE, $NODE);
		}
	}
}

# This section checks the file name(s) supplied to make sure they are correct
if ( $opt_f ) {

	# Set the SYNTAX flag
	$SYNTAX="OK";

	# Go through each file one at a time and confirm that it exists
	foreach $FILE (split /\s/, $opt_f ) {

		# Confirm the file exists
		if ( ! -f $FILE ) {
			print "\n$FILE is not a valid file name.\n\n";
			exit 0;
		}

		# Make sure the file name starts with a "/" 
		$FIRSTCHAR=substr($FILE,0,1);
		if ("$FIRSTCHAR" ne "/" ) {
			print "\nThe file name $FILE must be begin with a \"/\"\n\n";
			exit 0;
		}

		# Add $FILE to @FILE
		push (@FILE, $FILE);
	}
}

# This section checks the directory name(s) supplied to make sure they are correct
if ( $opt_d ) {

	# Set the SYNTAX flag
	$SYNTAX="OK";

	# Go through each directory one at a time and confirm that it exists
	foreach $DIR (split /\s/, $opt_d) {

		# Make sure $DIR is not one of the excluded directories
                foreach $EXCLUDED_DIR (@EXCLUDE1) {
                	if ( "$EXCLUDED_DIR" eq "$DIR" ) {
                        	print "\nCan not use $0 to update the entire directory $DIR.\n";
                        	print "$0 will not only allow all files and subdirectories\n";
				print "within $DIR to be updated.\n\n";
                        	exit 0;
                	}
		}

		# Make sure $DIR is not one of the excluded directories
                foreach $EXCLUDED_DIR (@EXCLUDE2) {
			$BASEDIR=(split /\//,$DIR)[1];
                	if ( "$EXCLUDED_DIR" eq "/$BASEDIR" ) {
                        	print "\nCan not use $0 to update the automounted directory $DIR.\n";
                        	print "$0 will not only allow any of directories, subdirectories\n";
				print "or files within $DIR to be updated.\n\n";
                        	exit 0;
                	}
		}

		# Confirm that the directory exists
		if ( ! -d $DIR ) {
			print "\n$DIR is not a valid directory name\n\n";
			exit 0;
		}

		# Make sure the directory name starts with a "/"
		$FIRSTCHAR=substr($DIR,0,1);
		if ("$FIRSTCHAR" ne "/" ) {
			print "\nThe directory name $DIR must be begin with a \"/\"\n\n";
			exit 0;
		}

		# Add $DIR to @DIR
		push (@DIR, $DIR);
	}
}

# This section checks the command(s) supplied to make sure they are correct
if ( $opt_c ) {

	# Set the SYNTAX flag
	$SYNTAX="OK";

	# Reomve any space that may be there after the ';' and before the next command
	$opt_c=~s/;\s/;/g;

	# Go through each command one at a time and confirm that it exists
	foreach $COMMAND (split /\;/, $opt_c) {

		# Set Command to the command itself, no arguments
		$Command=(split /\s/, $COMMAND)[0];
		
		# Set @ARG to the argument(s) that may be supplied to the command
		@ARG=(split /\s/, $COMMAND)[1..9];

		# Determine the path to the COMMAND and then verify
		# that the command exists
		chomp ($command=`which $Command 2>/dev/null`);
		if ( ! -x "$command" ) {
			print "\n$COMMAND is not a valid command name.\n";
			exit 0;
		}

		# Set COMMAND to $command
		$COMMAND="$command";
		
		# Remove any white space before or after the command $COMMAND
		$COMMAND=~s/\s//g;

		# Add the argument back to the command if there are any arguments
		(@ARG) and $COMMAND="$COMMAND @ARG";

		# Add $COMMAND to @COMMAND
        	push (@COMMAND, $COMMAND);
	}
}

# This section sets the ssh $TIMEOUT value, default $TIMEOUT value is 10 seconds
if ( $opt_t ) {

        # Set the SYNTAX flag
   	$SYNTAX="OK";

        # Confirm $opt_t is a number
        if ( $opt_t =~  m/\D/ ) {
                print "\nThe time out value \"$opt_t\" is invalid, only numbers are excepted\n";
                exit 0;
        } else {
                # Set $TIMEOUT to $opt_t
                $TIMEOUT="$opt_t";
        }
}

# Make sure the command syntax used was correct
( "$SYNTAX" ne "OK" ) and &USAGE;

# open the file handle HOST using the lshosts command
open (HOST,"/usr/bin/lshosts| sort |") or die "Unable to open the NIS host file $!\n";

# Remove $LOG id it exists
( -f $LOG ) and unlink $LOG;

# open the log file for writing
open (LOG,">>$LOG")or die "Can not open the file $LOG $!\n";

# Update the selected file(s)/directory or execute the command(s) on all of the nodes that are up
# except the one that this script is running on. Generate a list of host names by looking in the
# NIS host file for names that match nodeNN
LOOP: foreach $HOST (<HOST>) {
	
	# Set $HOST to the 2nd field in the host file
	$HOST=(split /\s/, $HOST)[0];

	# Exclude first line from lshosts
	( "$HOST" eq "HOST_NAME" ) && next LOOP;

	# Skip over any of the nodenames not in included
	if (@INCLUDE) {
		INCLUDE_NODE: foreach $INCLUDE_NODE (@INCLUDE) {

			$INCLUDE_MATCH="NO";

			if ( $HOST =~ m/$INCLUDE_NODE/ ) { 
				$INCLUDE_MATCH="YES";
				last INCLUDE_NODE;
			}
		}

		if ( $INCLUDE_MATCH eq "NO" ) {
			print "\nSkipping $HOST\n";
			next LOOP;
		}
	} 

	# Skip over any nodenames in exclude
	foreach $EXCLUDE_NODE (@EXCLUDE) {

		if ( $HOST =~ m/$EXCLUDE_NODE/ ) { 
			print "\nSkipping $HOST\n";
			next LOOP;
		}
	}

	# Determine if $HOST is up or down
	$PING="/bin/ping -c2 -w1 $HOST | grep -c \'100% packet loss\' 1>/dev/null 2>&1";
	$PING_STATUS=(system("/bin/sh -c \"$PING\""));

	if ( $PING_STATUS eq 0 ) {
		print "\n$HOST is down\n";
		print LOG "\n$HOST is down\n";
		close (LOG);
	} else {
		
		# open the file handle for the command rpcinfo -p, this will be used to make sure the node is up
		open (UPTEST,"/usr/sbin/rpcinfo -p $HOST 2>/dev/null|");
	
		# If $HOST is up, update the requested info
		if (<UPTEST>) {
	
			print "\n";
			print LOG "\n";
	
			close (LOG);
	
			# File Name(s) section
			foreach $FILE (@FILE) {
				system ("/usr/bin/rdist -o chknfs -c $FILE $HOST:$FILE | tee -a $LOG");
			}
	
			# Directory Name(s) section
			foreach $DIR (@DIR) {
				system ("/usr/bin/rdist -o chknfs -o remove -c $DIR $HOST:$DIR | tee -a $LOG");
			}
	
			# open the log file for writing
			open (LOG,">>$LOG")or die "Can not open the file $LOG $!\n";
	
			# Command(s) section
			foreach $COMMAND (@COMMAND) {
				print "$0 using ssh $HOST $COMMAND\n";
				print LOG "$0 using ssh $HOST $COMMAND\n";
	
				# Set RESULT to TIMEOUT if SSH fails
                		# alarm_call is a function to force a timeout of ssh
                		# on systems that it (ssh) hangs
                		$RESULT=alarm_call($TIMEOUT,'&SSH',$HOST,$COMMAND);
		
                		# if $RESULT is set to TIMEOUT, that means that the ssh process has failed
                		( $RESULT eq TIMEOUT ) and print "Problem with $HOST, pingable, but can not ssh to it\n";
			}
			close (LOG);
	
		} else {
			print "\n$HOST is down\n";
			print LOG "\n$HOST is down\n";
			close (LOG);
		}
	}
	close (UPTEST);
}

close (HOST);

print "\n\n##################################################\n";
printf "%-5s %-3s %-3s %-4s %-2s %-26s %-1s\n","#","The","log","file","is","$LOG","#";
print "##################################################\n\n\n";
