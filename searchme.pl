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
#          1.7 - Improve ranking - results are too broad.
#          1.6 - Show top searches and optionally additional.
#          1.5 - Introduce special file selection types with -s.
#          1.4 - Fix multiple start directories selection.
#          1.3 - Change how to specify multiple start directories.
#          1.2 - Ordered, ranked result output.
#          1.1 - Multiple terms refines search.
#          1.0 - Removing all hard-coded directory flags in favour of -I.
#          0.2 - Add -F for full indexing or -Q for quick index of EPLwork.
#          0.1 - Initial release. 
#          0.0 - Dev.
# Dependencies: 
#  pipe.pl
#
###############################################################################

use strict;
use warnings;
use vars qw/ %opt /;
use Getopt::Std;

my $VERSION            = qq{1.7};
my $TEMP_DIR           = "/tmp";
my $PIPE               = "pipe.pl";
my $MASTER_HASH_TABLE  = {};
my $MASTER_INV_FILE    = "$TEMP_DIR/search_inverted_index.idx";
chomp( my $HOME        = `env | egrep -e '^HOME=' | pipe.pl -W'=' -oc1` ); # Where to start the search.
my @SEARCH_DIRS        = ();
my $MAX_RESULTS        = 10;

#
# Message about this program and how to use it.
#
sub usage()
{
    print STDERR << "EOF";

	usage: $0 [-DiI{dirs}Mm{n}x?{search terms}]
Allows search of any keywords from scripts (*.sh and *.pl).

An inverted index is created, if one doesn't already exist in $TEMP_DIR, or the -i, or -I 
flag are specified. If -i is used, search starts in $HOME, which could take a while. Optionally
you can specify a starting directory, and all scripts in that directory and all others
below it will be indexed.

Once the index is created, searchme will use multiple search terms to narrow searches for key
words that exist within scripts. 

 -?{term1 term2 termN}: Output files that contain all the search terms in order from most likely to least.
 -D: Debug mode. Prints additional information to STDERR.
 -i: Create an index of search terms. Checks in $HOME dirs recursively.
 -I{dir1 dir2 dirN}: Create an index of search terms, recursively from specified directories.
 -m{hits}: Limit output to a specific number of results.
 -M: Show ranking, pipe delimited on output to STDOUT.
 -s{exp}: Include this 'find' globbing expression for additional search params other than '*.sh' and '*.pl'.
 -x: This (help) message.

example:
  searchme.pl -i # to build an inverted index staring in $HOME.
  searchme.pl -I"/s/sirsi/Unicorn/EPLwork/anisbet /s/sirsi/Unicorn/Bincustom" # to build an inverted index from here.
  searchme.pl -?password # Show all the scripts that contain the word 'password'.
  searchme.pl -?"juv soleil" # only files that contain all terms are output.
  searchme.pl -I"." -s"[R,r]eadme*.[t,m]*"    # search current directory and include search for files that match expression.
Version: $VERSION
EOF
    exit;
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
		if ( -d $dir )
		{
			printf STDERR "indexing directory: '%s'\n", $dir if ( $opt{'D'} );
			$results .= `find $dir -name "*.sh"`;
			$results .= `find $dir -name "*.pl"`;
			$results .= `find $dir -name "$opt{'s'}"` if ( $opt{'s'} );
		}
		else
		{
			printf STDERR "** error indexing directory: '%s'\n", $dir;
		}
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
			printf STDERR "'%s', ", $key;
		}
		printf STDERR "\n";
	}
	printf STDERR "%d keys written to index.\n", writeSortedTable( $MASTER_INV_FILE, $index );
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
	my @inverted_keys = keys %{$inverted_index};
	my @queries = split '\s+', $query;
	my $reverse_inverted_index = {};
	# Break apart the query words, and make a reverse inverted index of files keys and keyword matches.
	foreach my $q ( @queries )
	{
		if ( defined $q )
		{
			my @matches = grep /($q)/i, @inverted_keys;
			foreach my $match ( @matches )
			{
				# Get the value which is the files from the inverted index.
				my @files = split ':', $inverted_index->{$match};
				foreach my $file ( @files )
				{
					if ( exists $reverse_inverted_index->{ $file } )
					{
						$reverse_inverted_index->{ $file } += 1;
					}
					else
					{
						$reverse_inverted_index->{ $file } = 1;
					}
				}
			}
		}
	}
	# $inverted_index->{"k1"} = "f1:f2:f3";
	# $inverted_index->{"k2"} = "f3";
	# $reverse_inverted_index->{ f1 } = "3";
	# $reverse_inverted_index->{ f2 } = "1";
	# $reverse_inverted_index->{ f3 } = "2";
	my $output_result = {};
	# Display results.
	my @keys = sort { $reverse_inverted_index->{$a} <=> $reverse_inverted_index->{$b} } keys(%$reverse_inverted_index);
	@keys = reverse @keys;
	my $count = 0;
	foreach my $key ( @keys )
	{
		if ( $reverse_inverted_index->{ $key } >= scalar @queries )
		{
			if ( $count < $MAX_RESULTS )
			{
				printf "%d|", $reverse_inverted_index->{ $key } if ( $opt{'M'} );
				printf "%s\n", $key;
			}
			$count++;
		}
		else
		{
			last; # end early because they are ordered.
		}
	}
	printf STDERR "%d results found for %s.\n", $count, join ', ', @queries if ( $opt{'D'} );
}

# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
    my $opt_string = 'DiI:s:Mm:x?:';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ( $opt{'x'} );
	if ( $opt{'i'} )
	{
		push @SEARCH_DIRS, $HOME;
		create_inverted_index( $MASTER_HASH_TABLE );
	}
	elsif ( $opt{'I'} )
	{
		push @SEARCH_DIRS, split( '\s+', $opt{'I'} );
		create_inverted_index( $MASTER_HASH_TABLE );
	}
	$MAX_RESULTS = $opt{'m'} if ( $opt{'m'} );
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
	push @SEARCH_DIRS, $HOME;
	create_inverted_index( $MASTER_HASH_TABLE );
}
do_search( $opt{'?'}, $MASTER_HASH_TABLE ) if ( $opt{'?'} );
### code ends
# EOF
