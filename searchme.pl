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
#          1.0 - Removing all hardcoded dir flags in favour of -I.
#          0.2 - Add -F for full indexing or -Q for quick index of EPLwork.
#          0.1 - Initial release. 
#          0.0 - Dev. 
#
###############################################################################

use strict;
use warnings;
use vars qw/ %opt /;
use Getopt::Std;

my $VERSION            = qq{1.0};
my $TEMP_DIR           = "/tmp";
my $PIPE               = "pipe.pl";
my $MASTER_HASH_TABLE  = {};
my $MASTER_INV_FILE    = "$TEMP_DIR/search_inverted_index.idx";
chomp( my $HOME        = `env | egrep -e '^HOME=' | pipe.pl -W'=' -oc1` ); # Where to start the search.
my @SEARCH_DIRS        = ();

#
# Message about this program and how to use it.
#
sub usage()
{
    print STDERR << "EOF";

	usage: $0 [-DiI{dirs}Mx?{term}]
Allows all custom scripts and reports to be indexed and searchable based on keyword search.

 -D: Debug mode.
 -i: Create an index of search terms. Checks in $HOME dirs recursively.
 -I{dir1,dir2,...,dirN}: Create an index of search terms, recursively from specified directories.
 -?{term}: Search for files that contain the word {term}.
 -M: Show similar matching terms.
 -x: This (help) message.

example:
  $0 -i # to build an inverted index.
  $0 -?password # Show all the scripts that contain the word 'password'.
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
		if ( -e $dir )
		{
			$results  = `find $dir -name "*.sh"`;
			$results .= `find $dir -name "*.pl"`;
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
			printf STDERR "'%s'=>'%s'\n", $key, $index->{$key};
			# 'PASSED'=>'/s/sirsi/Unicorn/EPLwork/anisbet/WriteOffs/writeoff.pl:/s/sirsi/Unicorn/EPLwork/anisbet/Sip2/sip2cemu.pl'
		}
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
	my @keys = keys %{$inverted_index};
	my @matches = grep /($query)/i, @keys;
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
    my $opt_string = 'DiI:Mx?:';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ( $opt{'x'} );
	if ( $opt{'i'} )
	{
		push @SEARCH_DIRS, $HOME;
		create_inverted_index( $MASTER_HASH_TABLE );
	}
	elsif ( $opt{'I'} )
	{
		push @SEARCH_DIRS, split( ',\s+', $opt{'I'} );
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
	push @SEARCH_DIRS, $HOME;
	create_inverted_index( $MASTER_HASH_TABLE );
}
do_search( $opt{'?'}, $MASTER_HASH_TABLE ) if ( $opt{'?'} );
### code ends
# EOF
