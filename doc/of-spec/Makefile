TARGET=openflow-spec-v1.0.0

BIBTEX := bibtex
TGIF   := tgif
XFIG   := xfig
GNUPLOT:= gnuplot

SOURCES=$(TARGET).tex\
	appendix.tex\
	credits.tex

all: $(TARGET).ps
pdf: all
diff: $(TARGET)-diff.pdf

$(TARGET).pdf: Makefile  $(SOURCES)
	./make_latex_input.pl
	texi2pdf $(TARGET).tex

color: $(TARGET).pdf
	pdflatex $(TARGET).tex
	pdftops $(TARGET).pdf

$(TARGET)-diff.pdf: $(TARGET).pdf
	@if [ "$(DIFF_DIR)" = "" ] ; then \
		echo "Please set DIFF_DIR to point to the directory containing the spec to diff against" ;\
		echo "Example: $(MAKE) DIFF_DIR=<path_to_previous_spec> $@" ;\
		false ;\
	fi
	$(MAKE) -C $(DIFF_DIR)
	./make_diff.pl $(DIFF_DIR)
	texi2pdf $(TARGET)-diff.tex

$(TARGET).ps: $(TARGET).pdf
	pdftops $(TARGET).pdf

%.pdf : %.fig #Makefile
	fig2dev -L pdf -b 1 $< $@

%.eps : %.dia #Makefile
	dia --nosplash -e $@ $<

%.eps : %.obj
	TMPDIR=/tmp $(TGIF) -print -eps $<


%.pdf : %.eps #Makefile
	epstopdf $<

clean:
	rm -f *.aux *.log *.out *.bbl *.blg *~ *.bak $(TARGET).ps $(TARGET).pdf 
	rm -f *-diff.*
	rm -f $(TARGET).lot $(TARGET).lof $(TARGET).toc
	rm -rf define enum struct
