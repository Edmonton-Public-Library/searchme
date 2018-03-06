# Project Notes
Initialized: Mon Feb 26 14:02:21 MST 2018.
Created to create a reverse index of terms from all custom built scripts. This will help find scripts that perform tasks based on search terms. 

# Instructions for Running:
Periodically you will want to run ```searchme -i``` to create an index. After that use -? to find a script that uses the search term.
``` console
searchme.pl -x
```

Before you can query the in```searchme.pl -r```, the index will be created in ```$TEMP/search_inverted_index.idx```

# Product Description:
Perl script written by Andrew Nisbet for Edmonton Public Library, distributable by the enclosed license.

# Repository Information:
This product is under version control using Git.
[Visit GitHub](https://github.com/Edmonton-Public-Library)

# Dependencies:
* [pipe.pl](https://github.com/anisbet/pipe)
* getpathname

# Known Issues:
None
