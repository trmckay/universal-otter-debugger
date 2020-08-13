TOOL = pdflatex
DIR = tex
TEX = otter-db-multicycle.tex
TARGET = pdf

all:
	(cd $(DIR); $(TOOL) $(TEX); $(TOOL) $(TEX))
	mkdir -p $(TARGET)
	mv tex/*.pdf pdf
clean:
	(rm -f *.log; cd tex; rm -f *.aux *.out *.log *.toc)

remove:
	(rm -rf pdf *.log; cd tex; rm -f *.aux *.out *.log *.toc)
