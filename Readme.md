# Project Notes
Initialized: Mon Feb 26 14:02:21 MST 2018.
Allows search of any keywords from scripts (*.sh and *.pl).

An inverted index is created, if one doesn't already exist in $TEMP_DIR, or the -i, or -I 
flag are specified. If -i is used, search starts in $HOME, which could take a while. Optionally
you can specify a starting directory, and all scripts in that directory and all others
below it will be indexed.

Once the index is created, searchme will use multiple search terms to narrow searches for key
words that exist within scripts.
 
``` console
 -?{term1 term2 termN}: Output files that contain all the search terms in order from most likely to least.
 -D: Debug mode. Prints additional information to STDERR.
 -i: Create an index of search terms. Checks in $HOME dirs recursively.
 -I{dir1 dir2 dirN}: Create an index of search terms, recursively from specified directories.
 -M: Show ranking, pipe delimited on output to STDOUT.
 -x: This (help) message.
```

# examples:
``` console
searchme.pl -i # to build an inverted index staring in $HOME.
searchme.pl -I"/s/sirsi/Unicorn/EPLwork/anisbet /s/sirsi/Unicorn/Bincustom" # to build an inverted index from here.
searchme.pl -?password # Show all the scripts that contain the word 'password'.
searchme.pl -?"juv soleil" # only files that contain all terms are output.
```

# Product Description:
Perl script written by Andrew Nisbet for Edmonton Public Library, distributable by the enclosed license.

# Repository Information:
This product is under version control using Git.
[Visit GitHub](https://github.com/Edmonton-Public-Library)

# Dependencies:
* [pipe.pl](https://github.com/anisbet/pipe)

# Known Issues:
None
