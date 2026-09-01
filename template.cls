% Contain a template class.
%
% This file contains a template class.

% Define logic-related package.
\RequirePackage{etoolbox}

% Read the template class type.
\ProvidesClass{template}
\def\templateType{}
\DeclareOption*{\edef\templateType{\CurrentOption}}
\ProcessOptions\relax
\newtoggle{TemplateTypeLoaded}
\togglefalse{TemplateTypeLoaded}

% Define numbering-and-table-of-contents-related package.
\newcommand{\loadNumberingAndTOCPackage}{
    \newcommand{\templateCurrentNumMode}{}
    \newcommand{\templateCurrentTocMode}{}
    \newcommand{\templateResolveRootNumMode}[3]{
        \ifstrequal{##1}{num}{
            \def##2{num}
        }{
            \ifstrequal{##1}{nonum}{
                \def##2{nonum}
            }{
                \ClassError{template}
                    {Invalid \string##3 numbering mode '##1'}
                    {Use num or nonum.}
                \def##2{num}
            }
        }
    }
    \newcommand{\templateResolveRootTocMode}[3]{
        \ifstrequal{##1}{toc}{
            \def##2{toc}
        }{
            \ifstrequal{##1}{notoc}{
                \def##2{notoc}
            }{
                \ClassError{template}
                    {Invalid \string##3 table-of-contents mode '##1'}
                    {Use toc or notoc.}
                \def##2{toc}
            }
        }
    }
    \newcommand{\templateResolveNumMode}[3]{
        \ifstrequal{##1}{inh}{
            \ifdefempty{\templateCurrentNumMode}{
                \ClassError{template}
                    {\string##3 cannot inherit numbering mode without a parent}
                    {Use num or nonum, or place the command inside a parent.}
                \def##2{num}
            }{
                \edef##2{\templateCurrentNumMode}
            }
        }{
            \templateResolveRootNumMode{##1}{##2}{##3}
        }
    }
    \newcommand{\templateResolveTocMode}[3]{
        \ifstrequal{##1}{inh}{
            \ifdefempty{\templateCurrentTocMode}{
                \ClassError{template}
                    {\string##3 cannot inherit table-of-contents mode without a
                    parent}
                    {Use toc or notoc, or place the command inside a parent.}
                \def##2{toc}
            }{
                \edef##2{\templateCurrentTocMode}
            }
        }{
            \templateResolveRootTocMode{##1}{##2}{##3}
        }
    }
}

% Define color-related package.
\newcommand{\loadColorPackage}{
    \RequirePackage{xcolor}
    \definecolor{princetonOrange}{RGB}{232, 117, 17}
    \definecolor{crimson}{rgb}{0.86, 0.08, 0.24}
    \definecolor{forestGreen}{RGB}{34, 139, 34}
}

% Define formatting-related package.
\newcommand{\loadFormatPackage}{
    \@ifpackageloaded{hyperref}{
        \hypersetup{colorlinks=true, linkcolor=crimson, citecolor=crimson,
                    urlcolor=crimson}
    }{
        \RequirePackage[colorlinks=true, linkcolor=crimson, citecolor=crimson,
                        urlcolor=crimson]{hyperref}
    }
    \RequirePackage[T1]{fontenc}
}

% Define graphics-related package.
\newcommand{\loadGraphicsPackage}{
    \RequirePackage{tikz}
    \RequirePackage{caption}
    \RequirePackage{float}
    \captionsetup[figure]{labelfont=bf,labelsep=space}
    \NewDocumentCommand{\genFIG}{m m m m m m +m}{
        \templateResolveNumMode{##2}{\genFIGNumMode}{\genFIG}
        \templateResolveTocMode{##3}{\genFIGTocMode}{\genFIG}
        \ifdefstring{\genFIGNumMode}{num}{
            \ifdefstring{\genFIGTocMode}{toc}{
                \begin{figure}[##4]
                    \centering
                    \includegraphics[width=##5\textwidth]{##6}
                    \caption{(##1)\textbf{.} ##7}
                    \label{fig:##1}
                    \addcontentsline{toc}{subsection}{\protect\numberline{\thefigure}##1}
                \end{figure}
            }{
                \begin{figure}[##4]
                    \centering
                    \includegraphics[width=##5\textwidth]{##6}
                    \caption{(##1)\textbf{.} ##7}
                    \label{fig:##1}
                \end{figure}
            }
        }{
            \ifdefstring{\genFIGTocMode}{toc}{
                \begin{figure}[##4]
                    \centering
                    \includegraphics[width=##5\textwidth]{##6}
                    \caption*{\textbf{Figure} (##1)\textbf{.} ##7}
                    \phantomsection
                    \label{fig:##1}
                    \addcontentsline{toc}{subsection}{##1}
                \end{figure}
            }{
                \begin{figure}[##4]
                    \centering
                    \includegraphics[width=##5\textwidth]{##6}
                    \caption*{\textbf{Figure} (##1)\textbf{.} ##7}
                    \phantomsection
                    \label{fig:##1}
                \end{figure}
            }
        }
    }
}

% Define math-related package.
\newcommand{\loadMathPackage}{
    \RequirePackage{amsmath}
    \RequirePackage{amssymb}
    \RequirePackage{amsthm}
    \RequirePackage{cancel}
    \RequirePackage{mathdots}
    \newcommand{\Arg}{\mathrm{Arg} \:}
    \newcommand{\ra}{\rightarrow}
    \newcommand{\la}{\leftarrow}
    \newcommand{\p}{\partial}
    \newcommand{\floor}[1]{\left \lfloor ##1 \right \rfloor}
    \renewcommand{\d}{\mathrm{d}}
    \newcommand{\D}{\mathrm{D}}
    \newcommand{\bbm}{ \begin{bmatrix}}
    \newcommand{\ebm}{ \end{bmatrix} }
    \newcommand{\tr}{\mathrm{tr}}
    \newcommand{\td}[2]{\frac{\d ##1}{\d ##2}}
    \newcommand{\ep}{\varepsilon}
    \renewcommand{\Re}[1]{\mathrm{Re}\left(##1\right)}
    \renewcommand{\Im}[1]{\mathrm{Im}\left(##1\right)}
    \newcommand{\lra}{\Rightarrow}
    \newcommand{\lla}{\Leftarrow}
    \newcommand{\R}{\mathbb{R}}
    \newcommand{\C}{\mathbb{C}}
    \newcommand{\Q}{\mathbb{Q}}
    \newcommand{\norm}[1]{\left\| ##1 \right\|}
    \renewcommand{\exp}[1]{\mathrm{exp}\left( ##1 \right)}
    \newcommand{\Log}{\mathrm{Log} \:}
    \newcommand{\abs}[1]{\left| ##1 \right|}
    \renewcommand{\sb}[1]{\left[ ##1 \right]}
    \newcommand{\cb}[1]{\left\{ ##1 \right\}}
    \newcommand{\pb}[1]{\left( ##1 \right)}
    \newcommand{\innerprod}[2]{\langle ##1, ##2 \rangle}
    \newcommand{\pd}[3]{\frac{\partial^{##1} ##2}{\partial^{##1} ##3}}
    \newcommand{\sgn}{\text{sgn}}
    \newcommand{\E}[1]{\mathbb{E}\sb{##1}}
    \newcommand{\Var}[1]{\mathrm{Var}\sb{##1}}
    \newcommand{\Range}{\text{Range}\:}
    \newcommand{\mathinsection}[1]{\texorpdfstring{$##1$}{}}
    \theoremstyle{definition}
    \@ifundefined{theorem}{\newtheorem{theorem}{Theorem}[section]}{}
    \@ifundefined{theoremstar}{\newtheorem*{theoremstar}{Theorem}}{}
    \newcommand{\templateTheoremProofs}{}
    \newcommand{\templateProofsInitialSpacing}{}
    \newcommand{\templateQueueTheoremProof}[2]{
        \gappto\templateTheoremProofs{
            \genSubPart{Proof of \genREF{thm}{##1}}{inh}{notoc}{
                \phantomsection
                \label{proof:##1}
                ##2
            }
        }
    }
    \newcommand{\templateRenderTheoremProofs}{
        \ifdefempty{\templateTheoremProofs}{}{
            \genPart{Proofs}{nonum}{toc}{
                \templateProofsInitialSpacing
                \templateTheoremProofs
            }
        }
    }
    \NewDocumentCommand{\genTHM}{m m m +m +m}{
        \templateResolveNumMode{##2}{\genTHMNumMode}{\genTHM}
        \templateResolveTocMode{##3}{\genTHMTocMode}{\genTHM}
        \ifdefstring{\genTHMNumMode}{num}{
            \ifdefstring{\genTHMTocMode}{toc}{
                \begin{theorem}[##1]
                    \phantomsection
                    \addcontentsline{toc}{subsection}{\protect\numberline{\thetheorem}##1}
                    \label{thm:##1}
                    \edef\templateCurrentNumMode{\genTHMNumMode}
                    \edef\templateCurrentTocMode{\genTHMTocMode}
                    ##4
                \end{theorem}
            }{
                \begin{theorem}[##1]
                    \label{thm:##1}
                    \edef\templateCurrentNumMode{\genTHMNumMode}
                    \edef\templateCurrentTocMode{\genTHMTocMode}
                    ##4
                \end{theorem}
            }
        }{
            \ifdefstring{\genTHMTocMode}{toc}{
                \begin{theoremstar}[##1]
                    \phantomsection
                    \label{thm:##1}
                    \addcontentsline{toc}{subsection}{##1}
                    \edef\templateCurrentNumMode{\genTHMNumMode}
                    \edef\templateCurrentTocMode{\genTHMTocMode}
                    ##4
                \end{theoremstar}
            }{
                \begin{theoremstar}[##1]
                    \phantomsection
                    \label{thm:##1}
                    \edef\templateCurrentNumMode{\genTHMNumMode}
                    \edef\templateCurrentTocMode{\genTHMTocMode}
                    ##4
                \end{theoremstar}
            }
        }
        \begin{proof}
            See \hyperref[proof:##1]{Proof of ##1}.
        \end{proof}
        \templateQueueTheoremProof{##1}{##5}
    }
    \theoremstyle{definition}
    \@ifundefined{definition}{\newtheorem{definition}[theorem]{Definition}}{}
    \@ifundefined{definitionstar}{
        \newtheorem*{definitionstar}{Definition}
    }{}
    \NewDocumentCommand{\genDEF}{m m m +m}{
        \templateResolveNumMode{##2}{\genDEFNumMode}{\genDEF}
        \templateResolveTocMode{##3}{\genDEFTocMode}{\genDEF}
        \ifdefstring{\genDEFNumMode}{num}{
            \ifdefstring{\genDEFTocMode}{toc}{
                \begin{definition}[##1]
                    \phantomsection
                    \addcontentsline{toc}{subsection}{\protect\numberline{\thetheorem}##1}
                    \label{def:##1}
                    \edef\templateCurrentNumMode{\genDEFNumMode}
                    \edef\templateCurrentTocMode{\genDEFTocMode}
                    ##4
                \end{definition}
            }{
                \begin{definition}[##1]
                    \label{def:##1}
                    \edef\templateCurrentNumMode{\genDEFNumMode}
                    \edef\templateCurrentTocMode{\genDEFTocMode}
                    ##4
                \end{definition}
            }
        }{
            \ifdefstring{\genDEFTocMode}{toc}{
                \begin{definitionstar}[##1]
                    \phantomsection
                    \label{def:##1}
                    \addcontentsline{toc}{subsection}{##1}
                    \edef\templateCurrentNumMode{\genDEFNumMode}
                    \edef\templateCurrentTocMode{\genDEFTocMode}
                    ##4
                \end{definitionstar}
            }{
                \begin{definitionstar}[##1]
                    \phantomsection
                    \label{def:##1}
                    \edef\templateCurrentNumMode{\genDEFNumMode}
                    \edef\templateCurrentTocMode{\genDEFTocMode}
                    ##4
                \end{definitionstar}
            }
        }
    }
}

% Define references-related package.
\newcommand{\loadReferencesPackage}{
    \RequirePackage[
        backend=biber,
        style=numeric,
        sorting=ynt,
        maxbibnames=99
    ]{biblatex}
    \RequirePackage{tabularx}
    \addbibresource[glob]{./references/*/*.bib}
    \DeclareFieldFormat[article]{title}{##1}
    \DeclareFieldFormat[article]{journaltitle}{##1}
    \DeclareFieldFormat{url}{%
        \href{##1}{\begingroup\urlstyle{same}\nolinkurl{##1}\endgroup}}
    \newcolumntype{Z}{%
        !{\vrule width 1.2pt}
        @{\hspace{0.5em}}>{\centering\arraybackslash}m{2em}@{\hspace{0.5em}}|
        @{}X@{}
        !{\vrule width 1.2pt}}
    \newcolumntype{Y}{%
        @{\hspace{0.5em}}>{\bfseries\raggedright\arraybackslash}p{5.2em}@{\hspace{0.5em}}|
        @{\hspace{0.5em}}>{\raggedright\arraybackslash}%
        p{\dimexpr\linewidth-7.2em-\arrayrulewidth\relax}@{\hspace{0.5em}}}
    \newcommand{\templateReferenceOuterRule}{%
        \noalign{\hrule height 1.2pt}}
    \defbibenvironment{bibliography}
        {\list{}
            {\setlength{\leftmargin}{0pt}
             \setlength{\itemindent}{0pt}
             \setlength{\labelwidth}{0pt}
             \setlength{\labelsep}{0pt}
             \setlength{\itemsep}{\bibitemsep}
             \setlength{\parsep}{\bibparsep}}}
        {\endlist}
        {\item}
    \DeclareBibliographyDriver{article}{%
        \begin{tabularx}{\linewidth}{Z}
            \templateReferenceOuterRule
            \mkbibbrackets{\printfield{labelprefix}\printfield{labelnumber}} &
            \begin{tabular}{Y}
                Date: & \printfield{year}\tabularnewline\hline
                Authors: & \printnames{author}\tabularnewline\hline
                Title: & \printfield{title}\tabularnewline\hline
                Type: & Paper\tabularnewline\hline
                Publisher: & \printfield{journaltitle}\tabularnewline\hline
                Location: & \printfield{url}
            \end{tabular}\tabularnewline
            \templateReferenceOuterRule
        \end{tabularx}\nopunct
        \finentry
    }
    \DeclareFieldFormat[thesis]{title}{##1}
    \DeclareBibliographyDriver{thesis}{%
        \begin{tabularx}{\linewidth}{Z}
            \templateReferenceOuterRule
            \mkbibbrackets{\printfield{labelprefix}\printfield{labelnumber}} &
            \begin{tabular}{Y}
                Date: & \printfield{year}\tabularnewline\hline
                Authors: & \printnames{author}\tabularnewline\hline
                Title: & \printfield{title}\tabularnewline\hline
                Type: & Ph.D. Thesis\tabularnewline\hline
                School: & \printlist{institution}\tabularnewline\hline
                Location: & \printfield{url}
            \end{tabular}\tabularnewline
            \templateReferenceOuterRule
        \end{tabularx}\nopunct
        \finentry
    }
    \DeclareFieldFormat[book]{title}{##1}
    \DeclareBibliographyDriver{book}{%
        \begin{tabularx}{\linewidth}{Z}
            \templateReferenceOuterRule
            \mkbibbrackets{\printfield{labelprefix}\printfield{labelnumber}} &
            \begin{tabular}{Y}
                Date: & \printfield{year}\tabularnewline\hline
                Authors: & \printnames{author}\tabularnewline\hline
                Title: & \printfield{title}\tabularnewline\hline
                Type: & Book\tabularnewline\hline
                Publisher: & \printlist{publisher}\tabularnewline\hline
                Location: & \printfield{url}
            \end{tabular}\tabularnewline
            \templateReferenceOuterRule
        \end{tabularx}\nopunct
        \finentry
    }
    \DeclareFieldFormat[misc]{title}{##1}
    \DeclareBibliographyDriver{misc}{%
        \begin{tabularx}{\linewidth}{Z}
            \templateReferenceOuterRule
            \mkbibbrackets{\printfield{labelprefix}\printfield{labelnumber}} &
            \begin{tabular}{Y}
                Date: & \printfield{year}\tabularnewline\hline
                Authors: & \printnames{author}\tabularnewline\hline
                Title: & \printfield{title}\tabularnewline\hline
                Type: & Preprint\tabularnewline\hline
                Location: & \printfield{url}
            \end{tabular}\tabularnewline
            \templateReferenceOuterRule
        \end{tabularx}\nopunct
        \finentry
    }
    \newcommand{\genBack}{
        \templateRenderTheoremProofs
        \clearpage
        \phantomsection
        \printbibliography[title={References}]
    }
    \newcommand{\genREF}[2]{
        \hyperref[##1:##2]{##2}
    }
}

% Define loader for packages shared by all template types.
\newcommand{\loadPackagesSharedByAll}{
    \loadNumberingAndTOCPackage
    \loadColorPackage
    \loadFormatPackage
    \loadGraphicsPackage
    \loadMathPackage
}

% Define loader for packages shared by document template types.
\newcommand{\loadPackagesSharedByDocs}{
    \RequirePackage{etoc}
    \etocchecksemptiness
    \newcommand{\templateMainTOC}[1]{
        \etocsetnexttocdepth{##1}
        \tableofcontents
    }
    \newlength{\templateSubTOCIndent}
    \newcommand{\templateSubTOC}[2]{
        \begingroup
            \etocsetstyle{##1}{}{}{}{}
            \ifstrequal{##2}{section}{
                \renewcommand*\l@section{
                    \@dottedtocline{1}{\templateSubTOCIndent}{2.3em}
                }
            }{
                \ifstrequal{##2}{subsection}{
                    \renewcommand*\l@subsection{
                        \@dottedtocline{2}{\templateSubTOCIndent}{3.2em}
                    }
                }{
                    \renewcommand*\l@subsubsection{
                        \@dottedtocline{3}{\templateSubTOCIndent}{4.1em}
                    }
                }
            }
            \etocsetstyle{##2}{}{}{
                \@nameuse{l@##2}{
                    \numberline{\etocnumber}\etocname
                }{\etocpage}
            }{}
            \etocsettocstyle{}{}
            \etocsetnexttocdepth{##2}
            \localtableofcontents*
        \endgroup
    }
    \loadReferencesPackage
}

% DISSERTATION:
\ifdefstring{\templateType}{dissertation}{
    % Load the document class, load packages, and flag the template as loaded
    \LoadClass[11pt, oneside, openany]{book}
    \RequirePackage[margin=1in]{geometry}
    \RequirePackage{titlesec}
    \newlength{\templateChapterAfterSpace}
    \newlength{\templateSectionBeforeSpace}
    \newlength{\templateSectionAfterSpace}
    \newlength{\templateFigureBeforeSpace}
    \newlength{\templateCaptionSpace}
    \setlength{\templateChapterAfterSpace}{\baselineskip}
    \addtolength{\templateChapterAfterSpace}{-.6pt}
    \setlength{\templateSectionBeforeSpace}{\baselineskip}
    \addtolength{\templateSectionBeforeSpace}{-1.6pt}
    \setlength{\templateSectionAfterSpace}{\baselineskip}
    \addtolength{\templateSectionAfterSpace}{.7pt}
    \titleformat{\chapter}[hang]
        {\normalfont\huge\bfseries}{\thechapter}{1em}{}
    \titleformat{\section}[hang]
        {\normalfont\Large\bfseries}{\thesection}{1em}{}
    \titlespacing*{\chapter}{0pt}{-19pt}{\templateChapterAfterSpace}
    \titlespacing*{\section}{0pt}{\templateSectionBeforeSpace}{
        \templateSectionAfterSpace}
    \newcommand{\templateDissertationMainTOC}{
        \begingroup
            \etocsettocstyle{
                \chapter*{\contentsname}
                \vspace{-\baselineskip}
            }{}
            \templateMainTOC{section}
        \endgroup
    }
    \renewcommand{\chaptermark}[1]{\markboth{\thechapter\ #1}{\thechapter\ #1}}
    \loadPackagesSharedByAll
    \loadPackagesSharedByDocs
    \setlength{\templateSubTOCIndent}{-0.33em}
    \patchcmd{\l@chapter}
        {\vskip 1.0em \@plus\p@}
        {\vskip\baselineskip}
        {}
        {\ClassError{template}{Could not set dissertation TOC spacing}{}}
    \newtheoremstyle{templateDissertationDefinition}
        {\baselineskip}{\baselineskip}
        {\normalfont}{}{\bfseries}{.}{5pt plus 1pt minus 1pt}{}
    \csletcs{th@definition}{th@templateDissertationDefinition}
    \renewcommand{\templateProofsInitialSpacing}{\vspace{-2.2pt}}
    \setlength{\intextsep}{.7\baselineskip}
    \setlength{\templateFigureBeforeSpace}{-\intextsep}
    \addtolength{\templateFigureBeforeSpace}{1pt}
    \BeforeBeginEnvironment{figure}{
        \vspace{\templateFigureBeforeSpace}}
    \setlength{\templateCaptionSpace}{\baselineskip}
    \addtolength{\templateCaptionSpace}{2pt}
    \captionsetup[figure]{skip=\templateCaptionSpace}
    \setlength{\bibitemsep}{\baselineskip}
    \addtolength{\bibitemsep}{1.6pt}
    \renewcommand{\genBack}{
        \templateRenderTheoremProofs
        \clearpage
        \phantomsection
        \addcontentsline{toc}{chapter}{References}
        \printbibliography[title={References}]
    }
    \let\c@figure\c@theorem
    \renewcommand{\thefigure}{\thetheorem}
    \renewcommand{\theHfigure}{\theHtheorem}
    \toggletrue{TemplateTypeLoaded}
    % Define command that generates a chapter.
    \NewDocumentCommand{\genPart}{m m m +m}{
        \templateResolveRootNumMode{#2}{\genPartNumMode}{\genPart}
        \templateResolveRootTocMode{#3}{\genPartTocMode}{\genPart}
        \ifdefstring{\genPartNumMode}{num}{
            \ifdefstring{\genPartTocMode}{toc}{
                \chapter{#1}
                \label{part:#1}
            }{
                \let\templateAddContentsLine\addcontentsline
                \let\addcontentsline\@gobblethree
                \chapter{#1}
                \let\addcontentsline\templateAddContentsLine
                \label{part:#1}
            }
        }{
            \ifdefstring{\genPartTocMode}{toc}{
                \chapter*{#1}
                \phantomsection
                \addcontentsline{toc}{chapter}{#1}
            }{
                \chapter*{#1}
            }
        }
        \begingroup
            \edef\templateCurrentNumMode{\genPartNumMode}
            \edef\templateCurrentTocMode{\genPartTocMode}
            \ifdefstring{\genPartTocMode}{toc}{
                \templateSubTOC{subsection}{section}
            }{}
            #4
        \endgroup
    }
    % Define command that generates a section.
    \NewDocumentCommand{\genSubPart}{m m m +m}{
        \templateResolveNumMode{#2}{\genSubPartNumMode}{\genSubPart}
        \templateResolveTocMode{#3}{\genSubPartTocMode}{\genSubPart}
        \ifdefstring{\genSubPartNumMode}{num}{
            \ifdefstring{\genSubPartTocMode}{toc}{
                \section{#1}
                \label{subpart:#1}
            }{
                \let\templateAddContentsLine\addcontentsline
                \let\addcontentsline\@gobblethree
                \section{#1}
                \let\addcontentsline\templateAddContentsLine
                \label{subpart:#1}
            }
        }{
            \ifdefstring{\genSubPartTocMode}{toc}{
                \section*{#1}
                \phantomsection
                \addcontentsline{toc}{section}{#1}
            }{
                \section*{#1}
            }
        }
        \begingroup
            \edef\templateCurrentNumMode{\genSubPartNumMode}
            \edef\templateCurrentTocMode{\genSubPartTocMode}
            \ifdefstring{\genSubPartTocMode}{toc}{
                \templateSubTOC{section}{subsection}
            }{}
            #4
        \endgroup
    }
    % Define command that generates the front matter.
    \newcommand{\genFront}[8]{
        \frontmatter
        \hypersetup{pageanchor=false}
        \begin{titlepage}
            \centering
            {\huge\bfseries \raisebox{-3pt}[\height][\depth]{#1}\par}
            \vfill
            {#2\par}
            \vfill
            {
            A Dissertation\\
            Presented to the Faculty of\\
            #3\\
            in Candidacy for the Degree of\\
            Doctor of Philosophy\par
            }
            \vfill
            {
            Recommended for Acceptance\\
            by the Department of\\
            #4\\
            Adviser: #5\par
            }
            \vfill
            {#6\par}
            \vspace*{2pt}
        \end{titlepage}
        \hypersetup{pageanchor=true}
        \genPart{Abstract}{nonum}{notoc}{#7}
        \genPart{Acknowledgments}{nonum}{notoc}{#8}
        \templateDissertationMainTOC
        \mainmatter
    }
}{
    % Do nothing
}

% PREPRINT:
\ifdefstring{\templateType}{preprint}{
    % Load the document class, load packages, and flag the template as loaded
    \LoadClass[11pt]{article}
    \RequirePackage[margin=1in]{geometry}
    \RequirePackage{titlesec}
    \newlength{\templatePreprintSectionBeforeSpace}
    \newlength{\templatePreprintSectionAfterSpace}
    \newlength{\templatePreprintSubsectionBeforeSpace}
    \newlength{\templatePreprintSubsectionAfterSpace}
    \newlength{\templatePreprintFigureBeforeSpace}
    \newlength{\templatePreprintCaptionSpace}
    \setlength{\templatePreprintSectionBeforeSpace}{\baselineskip}
    \addtolength{\templatePreprintSectionBeforeSpace}{-1.6pt}
    \setlength{\templatePreprintSectionAfterSpace}{\baselineskip}
    \addtolength{\templatePreprintSectionAfterSpace}{.7pt}
    \setlength{\templatePreprintSubsectionBeforeSpace}{\baselineskip}
    \addtolength{\templatePreprintSubsectionBeforeSpace}{.5pt}
    \setlength{\templatePreprintSubsectionAfterSpace}{\baselineskip}
    \addtolength{\templatePreprintSubsectionAfterSpace}{.3pt}
    \titlespacing*{\section}{0pt}{\templatePreprintSectionBeforeSpace}{
        \templatePreprintSectionAfterSpace}
    \titlespacing*{\subsection}{0pt}{\templatePreprintSubsectionBeforeSpace}{
        \templatePreprintSubsectionAfterSpace}
    \RequirePackage{authblk}
    \RequirePackage[bottom]{footmisc}
    \renewcommand\@makefntext[1]{
        \parindent 1em
        \noindent\hb@xt@1.8em{\hss\@makefnmark}#1}
    \setlength{\affilsep}{1.4em}
    \patchcmd{\@maketitle}
        {\vskip 1.5em}
        {\vskip 1.31em}
        {}
        {\ClassError{template}{Could not set preprint author spacing}{}}
    \patchcmd{\@maketitle}
        {\vskip 1em}
        {\vskip .25em}
        {}
        {\ClassError{template}{Could not set preprint date spacing}{}}
    \patchcmd{\@maketitle}
        {\vskip 1.5em}
        {\vskip .255em}
        {}
        {\ClassError{template}{Could not set preprint abstract spacing}{}}
    \loadPackagesSharedByAll
    \loadPackagesSharedByDocs
    \setlength{\templateSubTOCIndent}{-0.33em}
    \patchcmd{\l@section}
        {\addvspace{1.0em \@plus\p@}}
        {\addvspace{\baselineskip}}
        {}
        {\ClassError{template}{Could not set preprint TOC spacing}{}}
    \patchcmd{\abstract}
        {\small}
        {\vspace{-12.14pt}\small}
        {}
        {\ClassError{template}{Could not set preprint abstract position}{}}
    \patchcmd{\abstract}
        {\vspace{-.5em}}
        {\vspace{.195em}}
        {}
        {\ClassError{template}{Could not set preprint abstract spacing}{}}
    \newtheoremstyle{templatePreprintDefinition}
        {\baselineskip}{\baselineskip}
        {\normalfont}{}{\bfseries}{.}{5pt plus 1pt minus 1pt}{}
    \csletcs{th@definition}{th@templatePreprintDefinition}
    \setlength{\intextsep}{.7\baselineskip}
    \setlength{\templatePreprintFigureBeforeSpace}{-\intextsep}
    \addtolength{\templatePreprintFigureBeforeSpace}{1pt}
    \BeforeBeginEnvironment{figure}{
        \vspace{\templatePreprintFigureBeforeSpace}}
    \setlength{\templatePreprintCaptionSpace}{\baselineskip}
    \addtolength{\templatePreprintCaptionSpace}{2pt}
    \captionsetup[figure]{skip=\templatePreprintCaptionSpace}
    \setlength{\bibitemsep}{\baselineskip}
    \addtolength{\bibitemsep}{1.6pt}
    \defbibheading{bibliography}[\refname]{
        \section*{#1}
        \vspace{-.5pt}}
    \renewcommand{\templateProofsInitialSpacing}{\vspace{-1.8pt}}
    \counterwithin{theorem}{subsection}
    \let\c@figure\c@theorem
    \renewcommand{\thefigure}{\thetheorem}
    \renewcommand{\theHfigure}{\theHtheorem}
    \csletcs{templatePreprintGenTHMCode}{genTHM code}
    \csletcs{templatePreprintGenDEFCode}{genDEF code}
    \csletcs{templatePreprintGenFIGCode}{genFIG code}
    \newcommand{\templatePreprintObjectToc}[1]{
        \begingroup
            \let\templatePreprintAddContentsLine\addcontentsline
            \renewcommand{\addcontentsline}[3]{
                \ifstrequal{##2}{subsection}{
                    \templatePreprintAddContentsLine
                        {##1}{subsubsection}{##3}
                }{
                    \templatePreprintAddContentsLine{##1}{##2}{##3}
                }
            }
            #1
        \endgroup
    }
    \RenewDocumentCommand{\genTHM}{m m m +m +m}{
        \templatePreprintObjectToc{
            \templatePreprintGenTHMCode{#1}{#2}{#3}{#4}{#5}
        }
    }
    \RenewDocumentCommand{\genDEF}{m m m +m}{
        \templatePreprintObjectToc{
            \templatePreprintGenDEFCode{#1}{#2}{#3}{#4}
        }
    }
    \RenewDocumentCommand{\genFIG}{m m m m m m +m}{
        \templatePreprintObjectToc{
            \templatePreprintGenFIGCode{#1}{#2}{#3}{#4}{#5}{#6}{#7}
        }
    }
    \toggletrue{TemplateTypeLoaded}
    % Define command that generates a section.
    \NewDocumentCommand{\genPart}{m m m +m}{
        \templateResolveRootNumMode{#2}{\genPartNumMode}{\genPart}
        \templateResolveRootTocMode{#3}{\genPartTocMode}{\genPart}
        \ifdefstring{\genPartNumMode}{num}{
            \ifdefstring{\genPartTocMode}{toc}{
                \section{#1}
                \label{part:#1}
            }{
                \let\templateAddContentsLine\addcontentsline
                \let\addcontentsline\@gobblethree
                \section{#1}
                \let\addcontentsline\templateAddContentsLine
                \label{part:#1}
            }
        }{
            \ifdefstring{\genPartTocMode}{toc}{
                \section*{#1}
                \phantomsection
                \addcontentsline{toc}{section}{#1}
            }{
                \section*{#1}
            }
        }
        \begingroup
            \edef\templateCurrentNumMode{\genPartNumMode}
            \edef\templateCurrentTocMode{\genPartTocMode}
            \ifdefstring{\genPartTocMode}{toc}{
                \templateSubTOC{subsubsection}{subsection}
            }{}
            #4
        \endgroup
    }
    % Define command that generates a subsection.
    \NewDocumentCommand{\genSubPart}{m m m +m}{
        \templateResolveNumMode{#2}{\genSubPartNumMode}{\genSubPart}
        \templateResolveTocMode{#3}{\genSubPartTocMode}{\genSubPart}
        \ifdefstring{\genSubPartNumMode}{num}{
            \ifdefstring{\genSubPartTocMode}{toc}{
                \subsection{#1}
                \label{subpart:#1}
            }{
                \let\templateAddContentsLine\addcontentsline
                \let\addcontentsline\@gobblethree
                \subsection{#1}
                \let\addcontentsline\templateAddContentsLine
                \label{subpart:#1}
            }
        }{
            \ifdefstring{\genSubPartTocMode}{toc}{
                \subsection*{#1}
                \phantomsection
                \addcontentsline{toc}{subsection}{#1}
            }{
                \subsection*{#1}
            }
        }
        \begingroup
            \edef\templateCurrentNumMode{\genSubPartNumMode}
            \edef\templateCurrentTocMode{\genSubPartTocMode}
            \ifdefstring{\genSubPartTocMode}{toc}{
                \templateSubTOC{subsection}{subsubsection}
            }{}
            #4
        \endgroup
    }
    % Define command that generates the front matter.
    \newcommand{\genFront}[7]{
        \title{\vspace{-1.5cm}#1\\[.939em]
            \large\normalfont\textit{preprint to be submitted to #2}}
        \author{#3\\#4}
        \date{#5}
        \maketitle
        \begin{abstract}
            #6
        \end{abstract}
        \begingroup
            \etocsettocstyle{
                \section*{\contentsname}
                \vspace{-\baselineskip}
            }{}
            \templateMainTOC{section}
        \endgroup
        \begingroup
            \renewcommand\thefootnote{}
            \renewcommand\theHfootnote{\arabic{footnote}}
            \NoHyper
                \footnotetext{\textbf{Acknowledgments:} #7}
            \endNoHyper
            \addtocounter{footnote}{-1}
        \endgroup
    }
    \renewcommand{\genBack}{
        \clearpage
        \templateRenderTheoremProofs
        \clearpage
        \phantomsection
        \addcontentsline{toc}{section}{References}
        \printbibliography[title={References}]
    }
}{
    % Do nothing
}

% PRESENTATION:
\ifdefstring{\templateType}{presentation}{
    \LoadClass{beamer}
    \RequirePackage{appendixnumberbeamer}
    \loadPackagesSharedByAll
    \toggletrue{TemplateTypeLoaded}
    \usetheme{Madrid}
    \usecolortheme[named=crimson]{structure}
    \setbeamercolor{alerted text}{use=structure,fg=structure.fg}
    \usefonttheme{serif}
    \setbeamertemplate{blocks}[rounded]
    \setbeamertemplate{navigation symbols}{}
    \setbeamertemplate{footline}[frame number]
    \setbeamertemplate{caption}[default]
    \renewcommand{\footnotesize}{\tiny}
    \newtoggle{allowAnimations}
    \toggletrue{allowAnimations}
    \newtoggle{presentationAppendix}
    \togglefalse{presentationAppendix}
    \newtoggle{firstPresentationSection}
    \toggletrue{firstPresentationSection}
    \newcommand{\SectionName}{}
    \newcommand{\fullOutline}{
        \begin{frame}{Outline}
            \iftoggle{presentationAppendix}{
                \tableofcontents[part=1]
            }{
                \tableofcontents[part=0]
            }
        \end{frame}
    }
    \newcommand{\sectionOutline}{
        \iftoggle{firstPresentationSection}{
            \addtocounter{framenumber}{-1}
            \togglefalse{firstPresentationSection}
        }{}
        \begin{frame}{Outline}
            \iftoggle{presentationAppendix}{
                \tableofcontents[part=1,currentsection]
            }{
                \tableofcontents[part=0,currentsection]
            }
        \end{frame}
    }
    \newcommand{\titleAndOutline}{
        \frame{\titlepage}
        \fullOutline
    }
    \newcommand{\genFront}[5]{
        \title{#1}
        \author{#2}
        \institute{
            \textbf{Affiliations:} #3\\[0.5em]
            \textbf{Acknowledgments:} #4
        }
        \date{#5}
        \titleAndOutline
    }
    \NewDocumentCommand{\genPart}{m +m}{
        \renewcommand{\SectionName}{#1}
        \section{#1}
        \sectionOutline
        #2
    }
    \NewDocumentCommand{\genSubPart}{m +m}{
        \iftoggle{presentationAppendix}{
            \iftoggle{allowAnimations}{
                \begin{frame}[noframenumbering]{#1}{\SectionName}
                \end{frame}
            }{}
            \begin{frame}[noframenumbering,shrink=10]{#1}{\SectionName}
                #2
            \end{frame}
        }{
            \iftoggle{allowAnimations}{
                \begin{frame}{#1}{\SectionName}
                \end{frame}
                \addtocounter{framenumber}{-1}
            }{}
            \begin{frame}[shrink=10]{#1}{\SectionName}
                #2
            \end{frame}
        }
    }
    \RenewDocumentCommand{\genTHM}{m +m}{
        \begin{block}{Theorem (#1)}
            \label{thm:#1}
            #2
        \end{block}
    }
    \RenewDocumentCommand{\genDEF}{m +m}{
        \begin{block}{Definition (#1)}
            \label{def:#1}
            #2
        \end{block}
    }
    \RenewDocumentCommand{\genFIG}{m m m m +m}{
        \begin{figure}[#2]
            \centering
            \includegraphics[width=#3\textwidth]{#4}
            \caption{(#1)\textbf{.} #5}
            \label{fig:#1}
        \end{figure}
    }
    \newcommand{\genREF}[2]{
        \hyperref[#1:#2]{#2}
    }
    \newcommand{\bo}[2]{
        \iftoggle{allowAnimations}{
            \begin{#1}[<+->]\setlength\itemsep{#2}
        }{
            \begin{#1}\setlength\itemsep{#2}
        }
    }
    \newcommand{\eo}[1]{
        \end{#1}
    }
    \newcommand{\bi}[2]{
        \vspace{#2}
        \begin{#1}\setlength\itemsep{#2}
    }
    \newcommand{\ei}[1]{
        \end{#1}
    }
    \newcommand{\genBack}{
        \appendix
        \setcounter{section}{0}
        \global\beamer@tocsectionnumber=0\relax
        \toggletrue{presentationAppendix}
        \setbeamertemplate{footline}{}
        \fullOutline
    }
    \renewcommand\appendixname{Appendix}
    \newcommand{\iitem}[1]{\item \textit{#1}}
    \newcommand{\bitem}[1]{\item \textbf{#1}}
}{
}

% NOTE:
\ifdefstring{\templateType}{note}{
    \LoadClass[11pt]{article}
    \RequirePackage[margin=1in]{geometry}
    \RequirePackage{titlesec}
    \newlength{\templateNoteSectionBeforeSpace}
    \newlength{\templateNoteSectionAfterSpace}
    \newlength{\templateNoteSubsectionBeforeSpace}
    \newlength{\templateNoteSubsectionAfterSpace}
    \newlength{\templateNoteFigureBeforeSpace}
    \newlength{\templateNoteCaptionSpace}
    \setlength{\templateNoteSectionBeforeSpace}{\baselineskip}
    \addtolength{\templateNoteSectionBeforeSpace}{-1.6pt}
    \setlength{\templateNoteSectionAfterSpace}{\baselineskip}
    \addtolength{\templateNoteSectionAfterSpace}{.7pt}
    \setlength{\templateNoteSubsectionBeforeSpace}{\baselineskip}
    \addtolength{\templateNoteSubsectionBeforeSpace}{.5pt}
    \setlength{\templateNoteSubsectionAfterSpace}{\baselineskip}
    \addtolength{\templateNoteSubsectionAfterSpace}{.3pt}
    \titlespacing*{\section}{0pt}{\templateNoteSectionBeforeSpace}{
        \templateNoteSectionAfterSpace}
    \titlespacing*{\subsection}{0pt}{\templateNoteSubsectionBeforeSpace}{
        \templateNoteSubsectionAfterSpace}
    \RequirePackage{authblk}
    \setlength{\affilsep}{1.4em}
    \patchcmd{\@maketitle}
        {\vskip 1.5em}
        {\vskip 1.31em}
        {}
        {\ClassError{template}{Could not set note author spacing}{}}
    \patchcmd{\@maketitle}
        {\vskip 1em}
        {\vskip .25em}
        {}
        {\ClassError{template}{Could not set note date spacing}{}}
    \patchcmd{\@maketitle}
        {\vskip 1.5em}
        {\vskip .255em}
        {}
        {\ClassError{template}{Could not set note contents spacing}{}}
    \loadPackagesSharedByAll
    \loadPackagesSharedByDocs
    \setlength{\templateSubTOCIndent}{-0.33em}
    \patchcmd{\l@section}
        {\addvspace{1.0em \@plus\p@}}
        {\addvspace{\baselineskip}}
        {}
        {\ClassError{template}{Could not set note TOC spacing}{}}
    \newtheoremstyle{templateNoteDefinition}
        {\baselineskip}{\baselineskip}
        {\normalfont}{}{\bfseries}{.}{5pt plus 1pt minus 1pt}{}
    \csletcs{th@definition}{th@templateNoteDefinition}
    \setlength{\intextsep}{.7\baselineskip}
    \setlength{\templateNoteFigureBeforeSpace}{-\intextsep}
    \addtolength{\templateNoteFigureBeforeSpace}{1pt}
    \BeforeBeginEnvironment{figure}{
        \vspace{\templateNoteFigureBeforeSpace}}
    \setlength{\templateNoteCaptionSpace}{\baselineskip}
    \addtolength{\templateNoteCaptionSpace}{2pt}
    \captionsetup[figure]{skip=\templateNoteCaptionSpace}
    \setlength{\bibitemsep}{\baselineskip}
    \addtolength{\bibitemsep}{1.6pt}
    \defbibheading{bibliography}[\refname]{
        \section*{#1}
        \vspace{-.5pt}}
    \renewcommand{\templateProofsInitialSpacing}{\vspace{-1.8pt}}
    \counterwithin{theorem}{subsection}
    \let\c@figure\c@theorem
    \renewcommand{\thefigure}{\thetheorem}
    \renewcommand{\theHfigure}{\theHtheorem}
    \csletcs{templateNoteGenTHMCode}{genTHM code}
    \csletcs{templateNoteGenDEFCode}{genDEF code}
    \csletcs{templateNoteGenFIGCode}{genFIG code}
    \newcommand{\templateNoteObjectToc}[1]{
        \begingroup
            \let\templateNoteAddContentsLine\addcontentsline
            \renewcommand{\addcontentsline}[3]{
                \ifstrequal{##2}{subsection}{
                    \templateNoteAddContentsLine
                        {##1}{subsubsection}{##3}
                }{
                    \templateNoteAddContentsLine{##1}{##2}{##3}
                }
            }
            #1
        \endgroup
    }
    \RenewDocumentCommand{\genTHM}{m m m +m +m}{
        \templateNoteObjectToc{
            \templateNoteGenTHMCode{#1}{#2}{#3}{#4}{#5}
        }
    }
    \RenewDocumentCommand{\genDEF}{m m m +m}{
        \templateNoteObjectToc{
            \templateNoteGenDEFCode{#1}{#2}{#3}{#4}
        }
    }
    \RenewDocumentCommand{\genFIG}{m m m m m m +m}{
        \templateNoteObjectToc{
            \templateNoteGenFIGCode{#1}{#2}{#3}{#4}{#5}{#6}{#7}
        }
    }
    \toggletrue{TemplateTypeLoaded}
    \NewDocumentCommand{\genPart}{m m m +m}{
        \templateResolveRootNumMode{#2}{\genPartNumMode}{\genPart}
        \templateResolveRootTocMode{#3}{\genPartTocMode}{\genPart}
        \ifdefstring{\genPartNumMode}{num}{
            \ifdefstring{\genPartTocMode}{toc}{
                \section{#1}
                \label{part:#1}
            }{
                \let\templateAddContentsLine\addcontentsline
                \let\addcontentsline\@gobblethree
                \section{#1}
                \let\addcontentsline\templateAddContentsLine
                \label{part:#1}
            }
        }{
            \ifdefstring{\genPartTocMode}{toc}{
                \section*{#1}
                \phantomsection
                \addcontentsline{toc}{section}{#1}
            }{
                \section*{#1}
            }
        }
        \begingroup
            \edef\templateCurrentNumMode{\genPartNumMode}
            \edef\templateCurrentTocMode{\genPartTocMode}
            \ifdefstring{\genPartTocMode}{toc}{
                \templateSubTOC{subsubsection}{subsection}
            }{}
            #4
        \endgroup
    }
    \NewDocumentCommand{\genSubPart}{m m m +m}{
        \templateResolveNumMode{#2}{\genSubPartNumMode}{\genSubPart}
        \templateResolveTocMode{#3}{\genSubPartTocMode}{\genSubPart}
        \ifdefstring{\genSubPartNumMode}{num}{
            \ifdefstring{\genSubPartTocMode}{toc}{
                \subsection{#1}
                \label{subpart:#1}
            }{
                \let\templateAddContentsLine\addcontentsline
                \let\addcontentsline\@gobblethree
                \subsection{#1}
                \let\addcontentsline\templateAddContentsLine
                \label{subpart:#1}
            }
        }{
            \ifdefstring{\genSubPartTocMode}{toc}{
                \subsection*{#1}
                \phantomsection
                \addcontentsline{toc}{subsection}{#1}
            }{
                \subsection*{#1}
            }
        }
        \begingroup
            \edef\templateCurrentNumMode{\genSubPartNumMode}
            \edef\templateCurrentTocMode{\genSubPartTocMode}
            \ifdefstring{\genSubPartTocMode}{toc}{
                \templateSubTOC{subsection}{subsubsection}
            }{}
            #4
        \endgroup
    }
    \newcommand{\genFront}[4]{
        \title{\vspace{-1.5cm}#1}
        \author{#2\\#3}
        \date{#4}
        \maketitle
        \begingroup
            \etocsettocstyle{
                \section*{\contentsname}
                \vspace{-\baselineskip}
            }{}
            \templateMainTOC{section}
        \endgroup
    }
    \renewcommand{\genBack}{
        \clearpage
        \templateRenderTheoremProofs
        \clearpage
        \phantomsection
        \addcontentsline{toc}{section}{References}
        \printbibliography[title={References}]
    }
}{
    % Do nothing
}

% Error if template type is not given or unknown.
\iftoggle{TemplateTypeLoaded}{
    % Do nothing
}{
    \ifdefempty{\templateType}{
        \ClassError{template}
            {No template type was supplied.}
            {Use dissertation, note, preprint, or presentation options.}
    }{
        \ClassError{template}
            {Unknown template type '\templateType'}
            {Use dissertation, note, preprint, or presentation options.}
    }
}

% Handle References
% ... I will do this later ...
