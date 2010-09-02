#!/usr/bin/perl -W
# vim:set shiftwidth=8 softtabstop=8 noexpandtab:

#
# Script to create a full diff version of the spec
#
# Written: 9/1/10 -- Glen Gibb (grg@stanford.edu)
#

use File::Find;
use File::Copy;

# Directories containing files generated from openflow.h
my @ofhSubdirs = ('define', 'enum', 'struct');

# Environments to strip/add to files generated from openflow.h
my @ofhOldHdrs = ('footnotesize', 'verbatim');
my @ofhNewHdrs = ('footnotesize', 'alltt');

# Files to process
my @texFiles;
my @ofhFiles;
my %fileMap;
my %inputMap;
my %hdrFiles;

my $old_dir;

parseCmdLine();

my $spec_new = getTexSrc(".");
my $spec_old = getTexSrc($old_dir);

print "$old_dir $spec_old $spec_new\n";

# Identify which texFiles to process
find(\&wanted_tex_files, '.');
find(\&wanted_ofh_files, @ofhSubdirs);

# Generate the diffs
genDiff("$old_dir/$spec_old", $spec_new);
genDiffs();

# Fix references to input texFiles in the diffs
updateDiffs();

# Postprocess the header diffs
postprocessHdrDiffs();

# Subroutine to check if a tex file name is wanted
sub wanted_tex_files {
	if (/\.tex$/ && ! /-diff\.tex$/ && ! /^\./ && ! /$spec_new/) {
		# Strip off any leading period
		my $fn = $File::Find::name;
		$fn =~ s/^\.\///;

		push @texFiles, $fn;
	}
}

# Subroutine to check if a file is wanted that was generated from the
# openflow.h file by make_latex_input.pl script
sub wanted_ofh_files {
	if (! /-diff$/ && ! /^\./ && -f $_) {
		push @ofhFiles, $File::Find::name;
	}
}

# Generate the diffs for each file
sub genDiffs {
	foreach my $file (@texFiles) {
		genDiff("$old_dir/$file", $file, 0);
	}

	foreach my $file (@ofhFiles) {
		genDiff("$old_dir/$file", $file, 1);
	}
}

# Generate the diff for a single file
sub genDiff {
	my ($old, $new, $isFromHdr) = @_;

	my $newbase = $new;
	$newbase =~ s/\.tex$//;

	my $diffbase = $new;
	my $diff = $new;
	if ($diff =~ /\.tex$/) {
		$diffbase =~ s/\.tex$/-diff/;
		$diff =~ s/\.tex$/-diff.tex/;
	}
	else {
		$diffbase .= '-diff';
		$diff .= '-diff';
	}

	# Record the mapping
	$fileMap{$new} = $diff;
	$inputMap{$newbase} = $diffbase;

	print "Generating diff for $new...\n";

	# Verify that the file exists in the old location
	if (-f $old) {
		if ($isFromHdr) {
			$old = preprocessHdr($old);
			$new = preprocessHdr($new);
		}

		`latexdiff $old $new > $diff`;

		unlink ($old, $new) if $isFromHdr;
	}
	else {
		if ($isFromHdr) {
			$new = preprocessHdr($new);
		}

		`latexdiff dummy.tex $new > $diff`;

		unlink ($new) if $isFromHdr;
	}
}

# Fix input references in diffs
sub updateDiffs {
	foreach my $file (values(%fileMap)) {
		print "Updating $file...\n";

		# Read in the contents of the file
		open (SRCFILE, "<$file");
		my @content = <SRCFILE>;
		my $content = join("", @content);
		close (SRCFILE);

		# Update references to input files
		while (my ($orig, $new) = each(%inputMap)) {
			$content =~ s/\\input{$orig}/\\input{$new}/g;
		}

		# Write the file
		open (DSTFILE, ">$file");
		print DSTFILE $content;
		close (DSTFILE);
	}
}

# Processes header files to remove the environment headers and to replace
# braces/spaces to better support expansion
sub preprocessHdr {
	my ($file) = @_;

	my $newFile = "$file-hdr";

	# Read in the source file
	open IN, "<$file";
	my @content = <IN>;
	close IN;

	# Check if we should drop the headers
	my $dropHdrs = 0;
	if (scalar(@content) > 2 * scalar(@ofhOldHdrs)) {
		$dropHdrs = 1;
		for (my $i = 0; $i < scalar(@ofhOldHdrs); $i++) {
			$dropHdrs &= ($content[$i] eq "\\begin{$ofhOldHdrs[$i]}\n");
		}
	}

	# Create the output file
	if ($dropHdrs == 1) {
		$hdrFiles{$file} = 1;
		open OUT, ">$newFile";

		# Drop the headers (eg. \begin{footnotesize})
		for (my $i = 0; $i < scalar(@ofhOldHdrs); $i++) {
			shift @content;
			pop @content;
		}

		# Process the remaining lines
		foreach my $line (@content) {
			chomp($line);

			$line =~ s/{/DIFF-LBRACE-DIFF/g;
			$line =~ s/}/DIFF-RBRACE-DIFF/g;
			$line =~ s/ / DIFF-SPACE-DIFF /g;

			print OUT "$line\n\n";
		}
		close OUT;
	}
	elsif (scalar(@content) != 0) {
		copy($file, $newFile);
	}

	return $newFile;
}

# Postprocess header files to reinsert environment headers and to restore the
# braces/spaces
sub postprocessHdr {
	my ($file) = @_;

	my $origFile = $file;
	$origFile =~ s/-diff$//;

	# Read the input file
	open IN, "<$file";
	my @content = <IN>;
	close IN;

	my $newFile = "$file-new";
	open OUT, ">$newFile";

	# Insert the environment headers if necessary
	if (exists($hdrFiles{$origFile})) {
		foreach my $hdr (@ofhNewHdrs) {
			print OUT "\\begin{$hdr}\n";
		}
	}

	# Replace the special tags inserted earlier
	foreach my $line (@content) {
		chomp($line);

		# Check for blank lines
		if ($line eq "") {
			print OUT "\n";
			next;
		}

		$line =~ s/(\\DIF(add|del)(begin|end))\s*/$1\{\}/g;

		$line =~ s/DIFF-LBRACE-DIFF/\\{/g;
		$line =~ s/DIFF-RBRACE-DIFF/\\}/g;

		$line =~ s/%DIF(ADD|DEL)CMD <.*//;

		$line =~ s/ //g;
		$line =~ s/DIFF-SPACE-DIFF/ /g;

		print OUT $line;
	}

	# Insert the environment footers if necessary
	if (exists($hdrFiles{$origFile})) {
		for (my $i = scalar(@ofhNewHdrs) - 1; $i >= 0; $i--) {
			print OUT "\\end{$ofhNewHdrs[$i]}\n";
		}
	}

	close OUT;

	move($newFile, $file);
	#copy($newFile, $file);

	return $newFile;
}

# Postprocess the header diffs
sub postprocessHdrDiffs {
	foreach my $file (@ofhFiles) {
		postprocessHdr("$file-diff");
	}
}

# Get the name of a tex file from a given directory
sub getTexSrc {
	my ($dir) = @_;

	my $target;

	# Check for a Makefile
	if (-f "$dir/Makefile") {
		$target = `make -C $dir -p -n | egrep '^TARGET[[:space:]]*=' | awk '{ print \$3; }'`;
	}
	else {
		die "Error: Can't locate Makefile in $dir";
	}

	# Verify that we have a target
	if (!defined($target) || $target eq '') {
		die "Unable to identify the target (TARGET) from $dir/Makefile";
	}

	chomp $target;
	$target .= ".tex";

	# Verify that we can find the target
	if (! -f "$dir/$target") {
		die "Cannot locate LaTeX file '$dir/$target'";
	}

	return $target;
}

# Parse command line args
sub parseCmdLine {
	if (scalar(@ARGV) != 1) {
		print "ERROR: Incorrect number of command line arguments specified\n\n";
		print "Usage:\n";
		print "\t$0 <prev_dir>\n\n";
		print "where";
		print "\torig_dir: directory containing previous version of spec\n\n";
		exit 1;
	}

	$old_dir = $ARGV[0];

	if (! -d $old_dir) {
		die "ERROR: Cannot locate directory '$old_dir' containing previous version of spec";
	}
}
