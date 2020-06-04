# Description
collExtractor implements an ngram extractor and a concordancer. The input text is tagged with TreeTagger. Ngram can be extracted based on tokens, tags, lemmas or all the three; same for the concordancer.

The collocation extractor currently works only with bigrams.

The concordancer is not 100% accurate. See "Known issues" section for more info.

# Installation
collExtractor was developed to work on Unix (Linux - macOS) and was tested on Ubuntu 18.04, Perl 5.26.1. There is currently no available version that works on Windows.

Before executing the program:
1) install the following dependencies.
2) **MODIFY THE "root_path" VARIALBLE in ./config/config.json !**

## External programs
Intall the following programs:

- TreeTagger in all the wanted languages (at least English or French to use the demo mode): follow intructions at https://cis.uni-muenchen.de/~schmid/tools/TreeTagger/
	+ **Don't forget to add TreeTagger's bin and cmd folder to your PATH variable!**
- Ngram Statistics Package (NSP): follow the instructions at http://ngram.sourceforge.net/
	+ **Don't forget to add NSP's bin folder to your PATH variable!**
- perl-doc : needs to be installed to read the man page. Besides that, the whole program will work without installing it.

## Perl packages
Install the following packages:

- WWW::Mechanize
- JSON::Parse

Each pakage can be installed with the command

    cpan install [package name]

# Usage:
perl collExtractor.pl --search coll [options] --input FILE

perl collExtractor.pl --search conc [options] --pattern PATTERN --input FILE

perl collExtractor.pl --demo LANG 

# Options:

	--help -h ?

print Synopsis and Options parts of the manual and exit
  
	--man

print the manual
  
	--input -i PATH

path (absolute or to the root of the program) to a text file (utf-8)

    --search -s

"coll" or "collocation" to find collocations;

"conc" or "concordances"to find the concordances of a pattern (see --pattern)
  
	--language -l LANGUAGE

language that should be used by TreeTagger. Write it exactly as is written in the tree-tagger command e.g. "english" for "tree-tagger-english"

	--method -m token|tag|lemma|all

define on what element(s) the search will be conducted. Tokens are case sensitive. Lemmas must be written in lower case.
	
	--sort freq|coll
  
Use only if --search=coll!

"freq" or "frequency" will write the result in reverse order of frequency ;

"t" will write the result in reverse order of t-score.

	--pattern PATTERN
 
Use only if --search=conc!

Pattern for which the concordances should be found. If several words are used, they should be written into quotes.

If --method=all, each "word" should be written as in the TreeTagger output i.e. "token tag lemma" (note the space between the elements, not before, not after) ; each "word" should be seperated by "<>".

To know what tagging taxonomy you should use, refer to the documentation of the version of TreeTagger you are using.

Example:

--pattern "in PRP in<>a AT0 a<>certain AJ0 certain"


	--n -n	 INT
  
If --search=coll, number of results that should be printed in the terminal.
If --search=conc, number of "words" that should be taken into account to the right and left of the node.

	--demo -d LANG

"fr" or "en". Activate the demo mode. It downloads text from Wikipedia in the language asked, and will list all its bigrams based on lemmas (not tokens!), sorted by frequency. The whole list will be printed into a file. The best results will also be printed on the screen, along with their frequency and their t-score.

# Examples

    perl collExtractor.pl --demo fr

    perl collExtractor.pl --search coll --sort freq --method all -l en --input ./demo/english2020Jun3.wiki

    perl collExtractor.pl -s coll --sort t -m lemma -l fr -i ./demo/french2020Jun3.wiki

    perl collExtractor.pl --search conc --method token --pattern ". Il" -l fr --input ./demo/french2020Jun3.wiki

    perl collExtractor.pl --s conc -m lemma -p ". il" --input ./demo/french2020Jun3.wiki -l fr

    perl collExtractor.pl --s conc -m all -p ". SENT .<>Il PRO:PER il" -l fr --input ./demo/french2020Jun3.wiki


# Changing parameters
## Default parameters
If you want to change default parameters, you can do so by modifying the ./config/config.json file.

You can define default vaules for the options -n, --language, --method and --sort. Those values will be used if no value is specified when the program is called.

## Other parameters
The following parameters can only be changed through the ./config/config.json file :
- "root\_path" : full path to the folder where this README.md and collExtractor.pl are. Please don't use any space in the path.
- "stopwords" : path to a file containing a list of stop words, i.e. words that will not be taken into account to build ngrams. Either an absolute path, or a path relative to the root\_path. This file must follow the format imposed by NSP : "Each stop token in FILE should be a Perl regular expression that occurs on a line by itself. This expression should be delimited by forward slashes, as in /REGEX/. All regular expression capabilities in Perl are supported except for regular expression modifiers (like the "i" /REGEX/i)." The default mode is OR, you can change it to AND. Please note that the stop list is applied only on the selected "method" elements (i.e. either tokens, tags, lemmas or the three of them).
- "joiner\_whole\_token" : when --method=all, the extracted concordances can be hard to read; that's why, by default, each "word" of the concordancer will then be separated by a line break and each concordance by two line breaks. You can change the character(s) that will separate each "word" in the concordancer by modifying this option (only applies for --method=all).

# Content of collExtractor
collExtractor is composed of a core program, collExtractor.pl, written in Perl 5.26. It comes with the package My::MyToken, stored in the lib folder.

A sample of French and English texts are available in the demo folder. Feel free to use them to try the program and its different options.
The data that will be created following your requests to the program will be stored in the corpora folder.

The config folder contains a few files that can be edited to personalize the output of the program (see "Changing parameters" section). I strongly recommand to not modify the 1TokenPerLine.tokenizer file. It is used to tell NSP that the text was already tokenized by TreeTagger.

The texts extracted from Wikipedia wit hthe option --demo are stored in ./demo/. All the other files produced by collExtractor (files with the tagged texts, ngram lists and concordance lines) are stored in ./corpora/.

## Output format
The format for the .tag files is the exact format used by TreeTagger.

In the .ngam files, you will find one ngram per line. each element of the ngram is separated from the other with <>. The second column contains the raw frequency of the ngram and the third column contains the t-score. The ngrams are sorted according to the method provided by using the option --sort, or by the default value given in the config.json file.

The first line of the .conc files is the number of concordances found. Each concordance is separated by two line breaks. When --method=all, by default each element of the concordance is on a diferent line (this can be modified in ./config/config/json). Otherwise, all the elements are written on one line, separated with white spaces.

# Known issues
1. Concordancer

Currently, the concordancer reads each element only one time, which means that if a match is identified, the search for other matches will start again after the end of the concordance line. In the same way, if the begining of a match is found, but it turns out not to be a full match, the search will start again after this false match.

The problem is the smallest when the context wanted to build the concordances is small and when the pattern to identify is small and rare.

This should be fixed soon.

2. Root_path

The program does not word if the root_path (in .config/config.json) contains white spaces.

3. Wiki texts

There are some (very few) encoding errors in the .wiki files.

# Author

Laurane Castiaux <laurane.castiaux@student.uclouvain.be>

Original project: https://github.com/Reyla98/collExtractor

# COPYRIGHT

Copyright (c) 2020 Laurane Castiaux.

Distributed and Licensed under provisions of the GNU General Public License v3.0, which is available at https://www.gnu.org/licenses/. 

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.


This program uses Ngram Statistics Package (NSP) - Copyright (C) 2000-2003, Ted Pedersen and Satanjeev Banerjee, distributed under GNU Public Licence.

This program uses TreeTagger developed by Helmut Schmid at the Institute for Computational Linguistics of the University of Stuttgart.
