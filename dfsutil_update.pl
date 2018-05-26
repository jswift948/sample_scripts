#!/bin/perl
# wpb_dfsutil_update.pl
# The purpose of this script is to update the dfslinks in the DFS 
# root \\$SERVER_NAME\$DFS_ROOT from the NIS automount maps needed for
# the DFS tree

# Written By: Jon Swift 07-12
# Updated 05/13, Changed logic to do 1 removal then 1 add. From doing all the removals then all the adds
#	This changes reduces the amount of time to readd links that were just removed
# Updated 10/13, merged the logic of the 3 DFS scripts into a single common script

# Set DOMAIN to the required DNS domain name
$DOMAIN="pwrutc.com";

# Set SERVER to the name of the host this script should be run on
$SERVER="SFU-CPC-01";

# Set SERVER_NAME to the host name of the system supporting the DFS tree
$SERVER_NAME="SFU-CPC-01";

# Set NFS_SERVER to the NFS server hold the automount file
$NFS_SERVER="goliath-new.$DOMAIN";

# Set IMPORT_DIR to the directory that conatins the dfsutil import data
$IMPORT_DIR="\\\\$NFS_SERVER\\export\\stds\\admin\\data";

# Set AUTO_MOUNTS to the name of the file conatining the NIS/automount 
# info. This file file is generated from the script wpb_build_dfs_imports.pwr, 
# which in run on node1001.pwrutc.com from cron. The file is formated to be 
# the same as the outpout of "dfscmd.exe /view \\$SERVER_NAME\$DFS_ROOT. 
# Example line below.
#    data/text  //goliath/export/data/public/text
$AUTO_MOUNTS="Z:/dfs_data_file";

# Set DFS_ROOT to be maintained by this script
$DFS_ROOT="CPCUNIX";

# Set DFSROOT to the name of the DFS root
$DFSROOT="\\\\$SERVER_NAME\\$DFS_ROOT";

# EMAIL_ADDRESS to the email address to send email when a problem is discovered
#$EMAIL_ADDRESS="jon.swift\@pwr.utc.com, renee.nys\@pw.utc.com, john.panattoni\@pwr.utc.com";
$EMAIL_ADDRESS="jon.swift\@pwr.utc.com";

# Set COMMENT to the comment to be added to DFS links added by this script
#$COMMENT="UNIXDFS";

# Set Misc. Variables
$CHANGE_REMOVE="YES";
$CHANGE_ADD="YES";
chomp ($HOST=`uname -n`);
chomp ($PROG=`basename $0`);
chomp($DATE_TIME=`C:/SFU/common/date.exe`);
($DATE0, $DATE1, $DATE2, $DATE3, $DATE4)=(split/\s/,$DATE_TIME)[0,1,2,3,5];
$DATE_TIME="$DATE0 $DATE1 $DATE2 $DATE3 $DATE4";
$LOG_FILE="C:/temp/cpc_dfsutil_update_log.txt";
$MIN_LINES="900";

# Set the following variables to null
$CURRENT_DFS_TABLES="";
$MAP="";

# Make sure this script is only run on $SERVER
if ( $HOST ne $SERVER ) {

	# Set ERROR_MESSAGE to the body of the email to be sent
	my $ERROR_MESSAGE="$PROG Error $DATE_TIME: This script is not supported on $HOST, only $SERVER\n";

	# Send email
	&EMAIL("$ERROR_MESSAGE");

	# Display error message
	print "$ERROR_MESSAGE\n";

	# Log Error message	
	&LOG("$ERROR_MESSAGE");

	# Exit the script
	exit 1;
}

# Open the file handle "MOUNT" for the mount.exe command
open(MOUNT,"C:/Windows/system32/net.exe use|") or die "Unable to use mount, $!\n";

# Loop through each from the output of the mount command looking for Z:
# If Z: is found, it's mounted
MNT: while (<MOUNT>) {

	if ( $_ =~ m/Z:/ ) {
		$MOUNTED="YES";
		last MNT;
	} else {
		$MOUNTED="NO";
	}
}
close(MOUNT);

# Umount Z: as needed
if ( $MOUNTED eq "YES" ) {
	print "Unmounting Z:\n";
	system("C:/Windows/system32/net.exe use /delete /yes Z:");
}

# Mount $IMPORT_DIR on Z:
print "Mounting $IMPORT_DIR on Z:\n";
system("C:/SFU/common/mount.exe $IMPORT_DIR -o anon Z:");

# Open the file handle "MOUNT" for the mount.exe command
open(MOUNT,"C:/Windows/system32/net.exe use|") or die "Unable to use mount, $!\n";

# Confirm Z: is mounted
MNT: while (<MOUNT>) {

	if ( $_ =~ m/Z:/ ) {
		$MOUNTED="YES";
		last MNT;
	} else {
		$MOUNTED="NO";
	}
}
close(MOUNT);

# Try again to mount $IMPORT_DIR on Z: as needed
if ( $MOUNTED eq "NO" ) {

	$MESSAGE="Mounting of Z: failed the first time. Attempting to mount $IMPORT_DIR on Z: a second time";
	print "$MESSAGE\n";

	# Log message	
	&LOG("$MESSAGE");
	system("C:/SFU/common/mount.exe $IMPORT_DIR -o anon Z:");
}

$MESSAGE="Starting DFS update of $DFSROOT";
&LOG("$MESSAGE");

# If the file $AUTO_MOUNTS exists open the file for reading
if ( -f "$AUTO_MOUNTS" ) {

	# Pre Set NUM_LINES to 0
	$NUM_LINES="0";

	# Open the file handle "AUTO_MOUNTS for the file $AUTO_MOUNTS for reading
	open (AUTO_MOUNTS,"$AUTO_MOUNTS") or die "Unable to open the file $AUTO_MOUNTS for reading, $!\n";

	# Write the contents of the file $AUTO_MOUNT to the hash table AUTOMOUNT_TABLES
	while (<AUTO_MOUNTS>) { 
		
		# Increment $NUM_LINES
		$NUM_LINES++;
	}

	# Close the file handle to the $AUTO_MOUNTS file
	close ("AUTO_MOUNTS");

	# Confirm $NUM_LINES is greater than $MIN_LINES
	if ( $NUM_LINES < $MIN_LINES ) {

		# Set ERROR_MESSAGE to the body of the email to be sent
		my $ERROR_MESSAGE="$PROG Error $DATE_TIME: The number of lines \"$NUM_LINES\" in the file $AUTO_MOUNTS iis less than \"$MIN_LINES\" on $HOST. Unable to continue";
	
		# Send email
		&EMAIL("$ERROR_MESSAGE");
	
		# Display error message
		print "$ERROR_MESSAGE\n";

		# Log Error message	
		&LOG("$ERROR_MESSAGE");
	
		# Exit the script
		exit 1;
	}

} else {

	# Set ERROR_MESSAGE to the body of the email to be sent
	my $ERROR_MESSAGE="$PROG Error $DATE_TIME: Unable to access the automount files $AUTO_MOUNTS on $HOST. Suspect problem with mounting $IMPORT_DIR on Z. Unable to continue";

	# Send email
	&EMAIL("$ERROR_MESSAGE");

	# Display error message
	print "$ERROR_MESSAGE\n";

	# Log Error message	
	&LOG("$ERROR_MESSAGE");

	# Exit the script
	exit 1;
}

# Open the file handle "AUTO_MOUNTS for the file $AUTO_MOUNTS for reading
open (AUTO_MOUNTS,"$AUTO_MOUNTS") or die "Unable to open the file $AUTO_MOUNTS for reading, $!\n";

# Write the contents of the file $AUTO_MOUNT to the hash table AUTOMOUNT_TABLES
while (<AUTO_MOUNTS>) { 
	
	chomp;

	# Split the line read in from $AUTO_MOUNTS
	($MNT_PNT,$MNT_SRC,$MNT_SRC2,$MNT_SRC3,$MNT_SRC4,$MNT_SRC5)=(split/\s/,$_);

	# If there is a 3rd field/2nd path to the data, append $MNT_SRC2 to $MNT_SRC
	("$MNT_SRC2" ne "" ) and $MNT_SRC="$MNT_SRC $MNT_SRC2";
	("$MNT_SRC3" ne "" ) and $MNT_SRC="$MNT_SRC $MNT_SRC3";
	("$MNT_SRC4" ne "" ) and $MNT_SRC="$MNT_SRC $MNT_SRC4";
	("$MNT_SRC5" ne "" ) and $MNT_SRC="$MNT_SRC $MNT_SRC5";
	
	# Make sure $MNT_PNT is not a null
	if ( "$MNT_PNT" ne "" ) {

		# Build the hash table AUTOMOUNT_TABLES, the key is the NIS mount point 
		# and the value to the actual source info

		# Before adding make sure there is not already a matcing entry
		if ( "$AUTOMOUNT_TABLES[$MNT_PNT]" eq "$MNT_SRC" ) {

			# Set ERROR_MESSAGE to the body of the email to be sent
			my $ERROR_MESSAGE="$PROG Error $DATE_TIME: Duplicate entry $MNT_PNT $MNT_SRC on $HOST";

			# Display error message
			print "$ERROR_MESSAGE\n";

			# Log Error message	
			&LOG("$ERROR_MESSAGE");

			# Send email
			&MAIL("$ERROR_MESSAGE");

		} else {
		
			# Add "Key=$MNT_PNT" "Value=$MNT_SRC" to the array $AUTOMOUNT_TABLES
			$AUTOMOUNT_TABLES{"$MNT_PNT"}="$MNT_SRC";	
		}
	}
}

# Close the file handle to the $AUTO_MOUNTS file
close ("AUTO_MOUNTS");

# Umount Z:
print "Umounting Z:\n";
system("C:/SFU/common/umount.exe Z:");

while ( "$CHANGE_REMOVE" eq "YES" or "$CHANGE_ADD" eq "YES" ) {

	# Build the array CURRENT_DFS_TABLES, add the current DFS linkx used
	&CURRENT_DFS;

	# Compare each entry in the CURRENT_DFS_TABLES to the entries in the AUTOMOUNT_TABLES.
	# If there are any entry in the CURRENT_DFS_TABLES that is not in the AUTOMOUNT_TABLES, 
	# or if the contents are different from the entry in the AUTOMOUNT_TABLES, remove that 
	# DFS link using the dfscmd commandand, and remove that entry from $CURRENT_DFS_TABLES.
	REMOVE_LINK: foreach $MNT_LINK (keys(%CURRENT_DFS_TABLES)) {
	
		# Remove any links that no longer are in the automount tables	
		if ( $CURRENT_DFS_TABLES{"$MNT_LINK"} ne $AUTOMOUNT_TABLES{"$MNT_LINK"} ) {
	
			# Display and log Comments
			$MESSAGE="Removing the link, $MNT_LINK";
			print "\n$MESSAGE\n";
			&LOG("$MESSAGE\n");
	
			# Convert all (forward slash) "/"'s to (back slash) "\"
			$MNT_LINK =~ s/\//\\/g;
	
			# Remove the old map from the dfs links
			#print "system(\"dfscmd /unmap $DFSROOT\\$MNT_LINK\")\n";
			system("dfscmd /unmap $DFSROOT\\$MNT_LINK");
			$CHANGE_REMOVE="YES";
			print "\n";
			
			# Set the REMOVE flag
			$REMOVE="YES";

			# Exit this loop
			last REMOVE_LINK;
			
		} else {
			# Set the REMOVE flag
			( $REMOVE ne "YES" ) and $REMOVE="NO";
		}
	}

	# Compare each entry in the AUTOMOUNT_TABLES to the entries in the CURRENT_DFS_TABLES. 
	# If there is an entry in AUTOMOUNT_TABLES that is not in CURRENT_DFS_TABLES and not 
	# in the MANUAL_TABLES use the dfscmd to add a new DFS link
	ADD_LINK: foreach $MNT_POINT(keys(%AUTOMOUNT_TABLES)) {

		# Set CHANGE_ADD Flag to NO. $CHANGE is used to decide if this loop should be run again
		$CHANGE_ADD="NO";
	
		# Add any new links that are in %AUTOMOUNT_TABLES but not in %CURRENT_DFS_TABLES
		# And not in %MANUAL_TABLES
		if ( $AUTOMOUNT_TABLES{"$MNT_POINT"} ne $CURRENT_DFS_TABLES{"$MNT_POINT"} and
			! $MANUAL_TABLES{"$MNT_POINT"} ) {

			# Set CHANGE_REMOVE Flag to YES. $CHANGE is used to decide if this loop should be run again
			$CHANGE_REMOVE="YES";
	
			# Display and log Comments
			$MESSAGE="Adding the link $MNT_POINT";
			print "\n$MESSAGE\n";
			&LOG("$MESSAGE\n");
	
			# Set MNT_PATH
			($MNT_PATH1, $MNT_PATH2,$MNT_PATH3,$MNT_PATH4,$MNT_PATH5)=(split/\s/,$AUTOMOUNT_TABLES{"$MNT_POINT"});
	
			# Convert all (forward slashes) "/" to (back slashes) "\"
			$MNT_POINT =~ s/\//\\/g;
			$MNT_PATH1 =~ s/\//\\/g;
			$MNT_PATH2 =~ s/\//\\/g;
			$MNT_PATH3 =~ s/\//\\/g;
			$MNT_PATH4 =~ s/\//\\/g;
			$MNT_PATH5 =~ s/\//\\/g;
	
			# Add the new automount entry to the dfs links
			#print "system \"dfscmd /map $DFSROOT\\$MNT_POINT $MNT_PATH1\"\n";
			system("dfscmd /map $DFSROOT\\$MNT_POINT $MNT_PATH1");

			if ( $MNT_PATH2 ne "" ) { 
				system("dfscmd /add $DFSROOT\\$MNT_POINT $MNT_PATH2");
				#print "system \"dfscmd /add $DFSROOT\\$MNT_POINT $MNT_PATH2\" \n";
				$CHANGE_ADD="YES";
			}
			if ( $MNT_PATH3 ne "" ) {
				system("dfscmd /add $DFSROOT\\$MNT_POINT $MNT_PATH3");
				#print "system \"dfscmd /add $DFSROOT\\$MNT_POINT\ $MNT_PATH3\" \n";
				$CHANGE_ADD="YES";
			}
			if ( $MNT_PATH4 ne "" ) { 
				system("dfscmd /add $DFSROOT\\$MNT_POINT $MNT_PATH4");
				#print "system \"dfscmd /add $DFSROOT\\$MNT_POINT $MNT_PATH4\" \n";
				$CHANGE_ADD="YES";
			}
			if ( $MNT_PATH5 ne "" ) {
				system("dfscmd /add $DFSROOT\\$MNT_POINT $MNT_PATH5");
				#print "system \"dfscmd /add $DFSROOT\\$MNT_POINT $MNT_PATH5\" \n";
				$CHANGE_ADD="YES";
			}
			print "\n";
	
			# Set ADD Flag
			$ADD="YES";
	
			# Set $MNT_PATH2 to null
			$MNT_PATH1=""; $MNT_PATH2="";

			# Exit this loop as needed
			last ADD_LINK;
		} else {
	
			# Set ADD Flag
			( $ADD ne "YES" ) and $ADD="NO";

			# Set CHANGE_REMOVE Flag to NO. $CHANGE is used to decide if this loop should be run again
			$CHANGE_REMOVE="NO";
		}
	}
}

# If there where no changes made to the DFS links (ADD set to NO or REMOVE set to NO) 
# print the following message.
if ( $ADD eq NO and $REMOVE = NO ) {
	$MESSAGE="All the DFS Links are up to date";
	print "\n$MESSAGE\n";	
	&LOG("$MESSAGE");
}

# The EMAIL function is used to email/page 
sub EMAIL {

	# Set MAIL to the full path of the mail command
	my $MAIL="C:\\SFU\\bin\\mailx";

        # $EMAIL_MESSAGE is the body of the email
        my ($EMAIL_MESSAGE)=@_;

        # Prepare error message
        my $ERROR="Error $DATE_TIME:  Can not open the $MAIL command";

        # Set email Subject
        $SUBJECT="$PROG Error on $HOST";

        # Open the mail command
        open (EMAIL,"|$MAIL -s \"$SUBJECT\" $EMAIL_ADDRESS");

       	# Send the email
        print EMAIL "$EMAIL_MESSAGE";

     	# Close the EMAIL file handle
        close (EMAIL);
}

# The LOG function is used to write messages to the the log file
sub LOG { 
	my ($MESSAGE)=@_;

	chomp($DATE_TIME=`C:/SFU/common/date.exe`);
	($DATE0, $DATE1, $DATE2, $DATE3, $DATE4)=(split/\s/,$DATE_TIME)[0,1,2,3,5];
	$DATE_TIME="$DATE0 $DATE1 $DATE2 $DATE3 $DATE4";

	open (LOG_FILE,">>$LOG_FILE") or die "Unable to open $LOG_FILE for writing, $!\n";
	print LOG_FILE "$DATE_TIME:  $MESSAGE\n";
	close (LOG_FILE);
}

# Function to read the current DFS Links
sub CURRENT_DFS {

	# Zero out the array %CURRENT_DFS_TABLES
	%CURRENT_DFS_TABLES=();	

	# Open the file handle "DFS" for the dfscmd command
	open(DFS,"dfscmd.exe /view $DFSROOT /full|") or die "Unable to use dfscmd, $!\n";

	# loop through the output lines from the dfscmd command and reformat
	# the output of it to be Mount Point, Primary Source, Secondary Source 
	# Secondary Source is optional
	while (<DFS>) {
	
		# Remove end of line character
		chomp;
	
		# Convert all "\" (back slash) to "/" (forward slash)
		$_ =~ s/\\/\//g;
		
		# Skip the last line "The command completed successfully"
		if ( $_ =~ m/completed successfully/ ) {
	
			next;
	
		# If this line contains the name of the DFS server, this is
		# the first line of output for this link/map. This line 
		# contains mount point name. IE.. home/UserID
		# Part 1
		} elsif ( $_ =~ m/$SERVER_NAME/ ) {
	
			# Determine if this a Manual link based on key comments.
			# Note that there must be at least 5 space before the
			# comment, and no more than 35 space before the comment.
			if ( $_ =~ m/.+ {5,35}WINDFS/ ) {
				$MANLINK="YES";
			} elsif ( $_ =~ m/.+ {5,35}DFSMANUAL/ ) {
				$MANLINK="YES";
			} else {
				$MANLINK="NO";
			}
	
			# Remove comments
			$_ =~ s/ {5,35}.+$//;
			
			# Set the array MAP to contain the contents of the link
			($DIR1,$DIR2,$DIR3,$DIR4)=(split/\//,$_)[4,5,6,7];
	
			# Skip any line that either $DIR1 or $DIR2 is null
			( $DIR1 eq "" or $DIR2 eq "" ) and next;
	
			if ( $DIR4 ne "" and $DIR3 ne "" ) {
				$MAP="$DIR1/$DIR2/$DIR3/$DIR4";
			} elsif ( $DIR4 eq "" and $DIR3 ne "" ) {
				$MAP="$DIR1/$DIR2/$DIR3";
			} elsif ( $DIR4 eq "" and $DIR3 eq "" ) {
				$MAP="$DIR1/$DIR2";
			}
	
			# Reset $NUM
			$NUM=1;
	
		} else {
			
			# This section strips out the pointer to the map
			# IE.. //goliath/export/home/usr01/UserID
			# Part 2

			# Add the links used in $MAP to @LINK
			($LINK)=(split/\s/,$_)[1];
	
			# Build the hash table "CURRENT_DFS_TABLES", using the MAP name as the key
			# and the LINK(s) as the value(s)
	
			# Skip Blank enties
			( $MAP eq "" or $LINK eq "" ) and next;
	
			# If the MAP has multiple paths $NUM will be set to 2 or higher
			if ( $NUM >= 2 ) {
				
				# Update either $CURRENT_DFS_TABLES or $MANUAL_TABLES
				# base on $MANLINK
				if ( $MANLINK eq "YES" ) {
					# Enter MAP/LINK into the hash table CURRENT_DFS_TABLES
					$FIRST_LINK=$MANUAL_TABLES{"$MAP"};
					$MANUAL_TABLES{"$MAP"}="";
					$MANUAL_TABLES{"$MAP"}="$FIRST_LINK $LINK";
	
				} else {
	
					# Enter MAP/LINK into the hash table CURRENT_DFS_TABLES
					$FIRST_LINK=$CURRENT_DFS_TABLES{"$MAP"};
					$CURRENT_DFS_TABLES{"$MAP"}="";
					$CURRENT_DFS_TABLES{"$MAP"}="$FIRST_LINK $LINK";
				}
				$FIRST_LINK="";
	
			} elsif ( $NUM == 1) {
				
				# Update either $CURRENT_DFS_TABLES or $MANUAL_TABLES
				# base on $MANLINK
				if ( $MANLINK eq "YES" ) {
					$MANUAL_TABLES{"$MAP"}="$LINK";
				} else {
					$CURRENT_DFS_TABLES{"$MAP"}="$LINK";
				}
			}
	
			# Increment $NUM
			$NUM++;
		}
	}
	
	# Close the DFS file handle
	close("DFS");
}
