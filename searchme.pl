#!/usr/bin/perl -w
###############################################################################
#
# Perl source file for project searchme 
#
# Allows searching of all custom scripts for key words.
#
#    Copyright (C) 2018  Andrew Nisbet, Edmonton Public Library
# The Edmonton Public Library respectfully acknowledges that we sit on
# Treaty 6 territory, traditional lands of First Nations and Metis people.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
# Author:  Andrew Nisbet, Edmonton Public Library
# Created: Mon Feb 26 14:02:21 MST 2018
# Rev: 
#          0.2 - Add -F for full indexing or -Q for quick index of EPLwork.
#          0.1 - Initial release. 
#          0.0 - Dev. 
#
###############################################################################

use strict;
use warnings;
use vars qw/ %opt /;
use Getopt::Std;

# Environment setup required by cron to run script because its daemon runs
# without assuming any environment settings and we need to use sirsi's.
###############################################################################
# *** Edit these to suit your environment *** #
$ENV{'PATH'}  = qq{:/s/sirsi/Unicorn/Bincustom:/s/sirsi/Unicorn/Bin:/usr/bin:/usr/sbin};
$ENV{'UPATH'} = qq{/s/sirsi/Unicorn/Config/upath};
###############################################################################
my $VERSION            = qq{0.2};
chomp( my $TEMP_DIR    = `getpathname tmp` );
chomp( my $TIME        = `date +%H%M%S` );
chomp ( my $DATE       = `date +%Y%m%d` );
my @CLEAN_UP_FILE_LIST = (); # List of file names that will be deleted at the end of the script if ! '-t'.
chomp( my $BINCUSTOM   = `getpathname bincustom` );
my $PIPE               = "$BINCUSTOM/pipe.pl";
chomp( my $CURRENT_DIR = `pwd` );
my $MASTER_HASH_TABLE  = {};
my $MASTER_INV_FILE    = "$TEMP_DIR/search_inverted_index.idx";
my $BASE_SEARCH_DIR    = "/s/sirsi/Unicorn"; # Where to start the search.
chomp( my $BIN_DIR     = `getpathname bin` );
chomp( my $BIN_CUST_DIR= `getpathname bincustom` );
my $EPL_JOB_DIR        = "/s/sirsi/Unicorn/EPLwork";
my @SEARCH_DIRS        = ();

#
# Message about this program and how to use it.
#
sub usage()
{
    print STDERR << "EOF";

	usage: $0 [-ADiMQtx?{term}]
Allows all custom scripts and reports to be indexed and searchable based on keyword search.

 -A: Just search Andrew's stuff. Wipes any previously existing index though.
     Checks in $EPL_JOB_DIR/anisbet dirs recursively.
 -D: Debug mode.
 -F: Build a complete full index. Otherwise look for scripts in the usual directories.
    Checks everything under $BASE_SEARCH_DIR recursively.
 -i: Create an index of search terms. Checks in $BIN_DIR, $BIN_CUST_DIR, and $EPL_JOB_DIR dirs recursively.
 -?{term}: Search for files that contain the word {term}.
 -M: Show similar matching terms.
 -Q: Quick index of all scripts under $BIN_CUST_DIR and $EPL_JOB_DIR.
 -t: Preserve temporary files in $TEMP_DIR.
 -x: This (help) message.

example:
  $0 -i # to build an inverted index.
  $0 -?password # Show all the scripts that contain the word 'password'.
Version: $VERSION
EOF
    exit;
}

# Removes all the temp files created during running of the script.
# param:  List of all the file names to clean up.
# return: <none>
sub clean_up
{
	foreach my $file ( @CLEAN_UP_FILE_LIST )
	{
		if ( $opt{'t'} )
		{
			printf STDERR "preserving file '%s' for review.\n", $file;
		}
		else
		{
			if ( -e  )
			{
				unlink $file;
				printf STDERR "removed '%s'\n", $file;
			}
		}
	}
}

# Writes data to a temp file and returns the name of the file with path.
# param:  unique name of temp file, like master_list.
# param:  data to write to file.
# return: name of the file that contains the list.
sub create_tmp_file( $$ )
{
	my $name    = shift;
	my $results = shift;
	my $sequence= sprintf "%02d", scalar @CLEAN_UP_FILE_LIST;
	my $master_file = "$TEMP_DIR/$name.$sequence.$DATE.";
	# Return just the file name if there are no results to report.
	return $master_file if ( ! $results );
	# Adding append here so that 2 commands can output to the same file. Simplifies selections in deactivate.
	open FH, ">>$master_file" or die "*** error opening '$master_file', $!\n";
	print FH $results;
	close FH;
	if ( grep( !/^($master_file)/, @CLEAN_UP_FILE_LIST ) )
	{
		# Add it to the list of files to clean if required at the end.
		push @CLEAN_UP_FILE_LIST, $master_file;
	}
	return $master_file;
}

# Writes the contents of a hash reference to file. Values are not stored.
# param:  file name string - path of file to write to.
# param:  table hash reference - data to write to file.
# return: the number of items written to file.
sub writeSortedTable( $$ )  ## Needs to be reworked to serialize arrays to file.
{
	my $fileName = shift;
	my $table    = shift;
	open TABLE, ">$fileName" or die "Serialization error writing '$fileName' $!\n";
	for my $key ( sort keys %{$table} )
	{
		print TABLE $key."=>".$table->{$key}."\n";
	}
	close TABLE;
	return scalar keys %$table;
}

# Reads the contents of a file into a hash reference.
# param:  file name string - path of file to write to.
# param:  Hash reference to place the data into.
# return: hash reference - table data.
sub readTable( $$ )  ## Needs to be reworked to de-serialize arrays from file.
{
	my ( $fileName ) = shift;
	my ( $table )    = shift;
	if ( -e $fileName )
	{
		open TABLE_FH, "<$fileName" or die "Serialization error reading '$fileName' $!\n";
		while ( <TABLE_FH> )
		{
			my $line = $_;
			chomp $line;
			my ( $key, $value ) = split '=>', $line;
			if ( defined $key && defined $value )
			{
				$table->{ $key } = $value;
			}
		}
		close TABLE_FH;
	}
	else
	{
		printf STDERR "*** error opening '$fileName', it doesn't seem to exist.\n";
		printf STDERR "Try re-running application with '-i' to create a new index.\n";
	}
}

# Go to all the directories under /s/sirsi/Unicorn and create a list of scripts.
# Read each line by line and parse out all words and create a key of the word and
# value of a list of fully qualified path name of the file it was found in. The name
# of the file should also be a keyword in the hash. As you find a pre-existing key
# add the new file name to the stored list. All keys should be in lower case, values
# must be as is.
# Example: 'juv' -> ('./hello.sh', './searchme.sh', './fuzzywuzzy.pl')
# param:  Inverted hash table (reference to a hashmap).
# return: None, but fills the hashmap with lists of file names that contain the same words.
sub create_inverted_index( $ )
{
	my $index = shift;
	printf STDERR "rebuilding index.\n";
	my $results = '';
	foreach my $dir ( @SEARCH_DIRS )
	{
		$results  = `find $dir -name "*.sh"`;
		$results .= `find $dir -name "*.pl"`;
	}
	my @files = split '\n', $results;
	$results = '';
	foreach my $file ( @files )
	{
		if ( $opt{'D'} )
		{
			printf STDERR "indexing file: '%s'\n", $file;
		}
		else
		{
			printf STDERR ".";
		}
		$results = `cat $file | $PIPE -W"(\\s+|\\.)" -h',' -nany | $PIPE -W',' -K | $PIPE -dc0 -zc0`;
		my @keywords = split '\n', $results;
		foreach my $keyword ( @keywords )
		{
			if ( exists $index->{ $keyword } )
			{
				$index->{ $keyword } .= ":$file";
			}
			else
			{
				$index->{ $keyword } = "$file";
			}
		}
	}
	if ( $opt{'D'} )
	{
		foreach my $key ( keys %{$index} )
		{
			printf STDERR "\n\n'%s'=>'%s'\n", $key, $index->{$key};
			# 'PASSED'=>'/s/sirsi/Unicorn/EPLwork/anisbet/WriteOffs/writeoff.pl:/s/sirsi/Unicorn/EPLwork/anisbet/Sip2/sip2cemu.pl'
		}
		printf STDERR "%d keys written to index.\n", writeSortedTable( $MASTER_INV_FILE, $index );
	}
	printf STDERR "done.\n";
}

# Search the table for the terms.
# param:  search term string.
# param:  index (hash table reference).
# return: none.
sub do_search( $$ )
{
	my $query          = shift;
	my $inverted_index = shift;
	my @keys = keys %{$inverted_index};
	$query = uc $query;
	my @matches = grep /($query)/, @keys;
	my $output_result = {};
	foreach my $match ( @matches )
	{
		my @multi_match_file_names = split ':', $inverted_index->{$match};
		foreach my $multi_file_name ( @multi_match_file_names )
		{
			if ( exists $output_result->{$multi_file_name} && defined $multi_file_name )
			{
				$output_result->{$multi_file_name} .= ":" . $match;
			}
			else
			{
				$output_result->{$multi_file_name} = $match;
			}
		}
	}
	# Display results. 
	foreach my $key ( keys %{$output_result} )
	{
		if ( $opt{'M'} ) # show match words.
		{
			printf "%s::%s\n", $key, $output_result->{ $key };
		}
		else
		{
			printf "%s\n", $key;
		}
	}
}

# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
    my $opt_string = 'ADFiMQtx?:';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ( $opt{'x'} );
	if ( $opt{'F'} )
	{
		push @SEARCH_DIRS, $BASE_SEARCH_DIR; # Where to start the search.
		create_inverted_index( $MASTER_HASH_TABLE );
	}
	elsif ( $opt{'Q'} )
	{
		push @SEARCH_DIRS, $BIN_CUST_DIR;
		push @SEARCH_DIRS, $EPL_JOB_DIR;
		create_inverted_index( $MASTER_HASH_TABLE );
	}
	elsif ( $opt{'A'} )
	{
		push @SEARCH_DIRS, "/s/sirsi/Unicorn/EPLwork/anisbet";
		create_inverted_index( $MASTER_HASH_TABLE );
	}
	elsif ( $opt{'i'} )
	{
		push @SEARCH_DIRS, $BIN_DIR;
		push @SEARCH_DIRS, $BIN_CUST_DIR;
		push @SEARCH_DIRS, $EPL_JOB_DIR;
		create_inverted_index( $MASTER_HASH_TABLE );
	}
}

init();
### code starts
# Read in the index.
if ( -s $MASTER_INV_FILE )
{
	readTable( $MASTER_INV_FILE, $MASTER_HASH_TABLE );
}
else # Rebuild the index.
{
	create_inverted_index( $MASTER_HASH_TABLE );
}
do_search( $opt{'?'}, $MASTER_HASH_TABLE );
### code ends
clean_up();
# EOF
