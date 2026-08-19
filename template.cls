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
    \RequirePackage[colorlinks=true, linkcolor=crimson, citecolor=crimson,
                    urlcolor=crimson]{hyperref}
    \RequirePackage[T1]{fontenc}
}

% Define graphics-related package.
\newcommand{\loadGraphicsPackage}{
    \RequirePackage{tikz}
    \RequirePackage{caption}
    \RequirePackage{float}
    \NewDocumentCommand{\genFIG}{m m m m m m +m}{
        \templateResolveNumMode{##2}{\genFIGNumMode}{\genFIG}
        \templateResolveTocMode{##3}{\genFIGTocMode}{\genFIG}
        \ifdefstring{\genFIGNumMode}{num}{
            \ifdefstring{\genFIGTocMode}{toc}{
                \begin{figure}[##4]
                    \centering
                    \includegraphics[width=##5\textwidth]{##6}
                    \caption{\textbf{##1} ##7}
                    \label{fig:##1}
                    \addcontentsline{toc}{subsection}{
                        \protect\numberline{\thefigure}
                        ##1
                    }
                \end{figure}
            }{
                \begin{figure}[##4]
                    \centering
                    \includegraphics[width=##5\textwidth]{##6}
                    \caption{\textbf{##1} ##7}
                    \label{fig:##1}
                \end{figure}
            }
        }{
            \ifdefstring{\genFIGTocMode}{toc}{
                \begin{figure}[##4]
                    \centering
                    \includegraphics[width=##5\textwidth]{##6}
                    \caption*{\textbf{##1} ##7}
                    \phantomsection
                    \addcontentsline{toc}{subsection}{##1}
                \end{figure}
            }{
                \begin{figure}[##4]
                    \centering
                    \includegraphics[width=##5\textwidth]{##6}
                    \caption*{\textbf{##1} ##7}
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
    \newcommand{\ra}{\rightarrow}
    \newcommand{\la}{\leftarrow}
    \renewcommand{\l}{\left}
    \renewcommand{\r}{\right}
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
    \newcommand{\Arg}{\mathrm{Arg} \:}
    \newcommand{\Log}{\mathrm{Log} \:}
    \newcommand{\abs}[1]{\l| ##1 \r|}
    \renewcommand{\sb}[1]{\left[ ##1 \right]}
    \newcommand{\cb}[1]{\l\{ ##1 \r\}}
    \newcommand{\pb}[1]{\l( ##1 \r)}
    \newcommand{\innerprod}[2]{\langle ##1, ##2 \rangle}
    \newcommand{\pd}[3]{\frac{\partial^{##1} ##2}{\partial^{##1} ##3}}
    \newcommand{\sgn}{\text{sgn}}
    \newcommand{\E}[1]{\mathbb{E}\sb{##1}}
    \newcommand{\Var}[1]{\mathrm{Var}\sb{##1}}
    \newcommand{\Range}{\text{Range}\:}
    \newcommand{\mathinsection}[1]{\texorpdfstring{$##1$}{}}
    \theoremstyle{definition}
    \newtheorem{theorem}{Theorem}[section]
    \newtheorem*{theoremstar}{Theorem}
    \NewDocumentCommand{\genTHM}{m m m +m}{
        \templateResolveNumMode{##2}{\genTHMNumMode}{\genTHM}
        \templateResolveTocMode{##3}{\genTHMTocMode}{\genTHM}
        \ifdefstring{\genTHMNumMode}{num}{
            \ifdefstring{\genTHMTocMode}{toc}{
                \begin{theorem}[##1]
                    \phantomsection
                    \addcontentsline{toc}{subsection}{
                        \protect\numberline{\thetheorem}
                        ##1
                    }
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
                    \addcontentsline{toc}{subsection}{##1}
                    \edef\templateCurrentNumMode{\genTHMNumMode}
                    \edef\templateCurrentTocMode{\genTHMTocMode}
                    ##4
                \end{theoremstar}
            }{
                \begin{theoremstar}[##1]
                    \edef\templateCurrentNumMode{\genTHMNumMode}
                    \edef\templateCurrentTocMode{\genTHMTocMode}
                    ##4
                \end{theoremstar}
            }
        }
    }
    \theoremstyle{definition}
    \newtheorem{definition}[theorem]{Definition}
    \newtheorem*{definitionstar}{Definition}
    \NewDocumentCommand{\genDEF}{m m m +m}{
        \templateResolveNumMode{##2}{\genDEFNumMode}{\genDEF}
        \templateResolveTocMode{##3}{\genDEFTocMode}{\genDEF}
        \ifdefstring{\genDEFNumMode}{num}{
            \ifdefstring{\genDEFTocMode}{toc}{
                \begin{definition}[##1]
                    \phantomsection
                    \addcontentsline{toc}{subsection}{
                        \protect\numberline{\thetheorem}
                        ##1
                    }
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
                    \addcontentsline{toc}{subsection}{##1}
                    \edef\templateCurrentNumMode{\genDEFNumMode}
                    \edef\templateCurrentTocMode{\genDEFTocMode}
                    ##4
                \end{definitionstar}
            }{
                \begin{definitionstar}[##1]
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
    \usepackage[
        backend=biber,
        style=numeric,
        sorting=ynt,
        maxbibnames=99
    ]{biblatex}
    \addbibresource{./code_assets/references.bib}
    \DeclareFieldFormat[article]{title}{##1}
    \DeclareFieldFormat{url}{\href{##1}{Download Location}}
    \DeclareBibliographyDriver{article}{%
        \textbf{Date:} \printfield{year}\par
        \textbf{Authors:} \printnames{author}\par
        \textbf{Title:} \printfield{title}\par
        \textbf{Type:} Paper\par
        \textbf{Publisher:} \printfield{journaltitle}\par
        \printfield{url}\nopunct
        \finentry
    }
    \DeclareFieldFormat[thesis]{title}{##1}
    \DeclareBibliographyDriver{thesis}{%
        \textbf{Date:} \printfield{year}\par
        \textbf{Authors:} \printnames{author}\par
        \textbf{Title:} \printfield{title}\par
        \textbf{Type:} Ph.D. Thesis\par
        \textbf{School:} \printlist{institution}\par
        \printfield{url}\nopunct
        \finentry
    }
    \DeclareFieldFormat[book]{title}{##1}
    \DeclareBibliographyDriver{book}{%
        \textbf{Date:} \printfield{year}\par
        \textbf{Authors:} \printnames{author}\par
        \textbf{Title:} \printfield{title}\par
        \textbf{Type:} Book \par
        \textbf{Publisher:} \printlist{publisher}\par
        \printfield{url}\nopunct
        \finentry
    }
    \DeclareFieldFormat[misc]{title}{##1}
    \DeclareBibliographyDriver{misc}{%
        \textbf{Date:} \printfield{year}\par
        \textbf{Authors:} \printnames{author}\par
        \textbf{Title:} \printfield{title}\par
        \textbf{Type:} Preprint \par
        \printfield{url}\nopunct
        \finentry
    }
    \newcommand{\genBack}{
        \clearpage
        \phantomsection
        \addcontentsline{toc}{chapter}{References}
        \printbibliography[title={References}]
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
    \loadReferencesPackage
}

% DISSERTATION:
\ifdefstring{\templateType}{dissertation}{
    % Load the document class, load packages, and flag the template as loaded
    \LoadClass[11pt, oneside, openany]{book}
    \RequirePackage[margin=1in]{geometry}
    \loadPackagesSharedByAll
    \loadPackagesSharedByDocs
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
            #4
        \endgroup
    }
    % Define command that generates the front matter.
    \newcommand{\genFront}[8]{
        \frontmatter
        \hypersetup{pageanchor=false}
        \begin{titlepage}
            \centering
            {\LARGE\bfseries #1\par}
            \vfill
            {\Large #2\par}
            \vfill
            {\large
            A Dissertation\\
            Presented to the Faculty of\\
            #3\\
            in Candidacy for the Degree of\\
            Doctor of Philosophy\par
            }
            \vfill
            {\large
            Recommended for Acceptance\\
            by the Department of\\
            #4\\
            Adviser: #5\par
            }
            \vfill
            {\large #6\par}
        \end{titlepage}
        \hypersetup{pageanchor=true}
        \genPart{Abstract}{nonum}{notoc}{#7}
        \genPart{Acknowledgments}{nonum}{notoc}{#8}
        \tableofcontents
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
    \loadPackagesSharedByAll
    \loadPackagesSharedByDocs
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
            #4
        \endgroup
    }
    % Define command that generates the front matter.
    \newcommand{\genFront}[8]{
        % Do something
        \tableofcontents
    }
}{
    % Do nothing
}

% PRESENTATION:
\ifdefstring{\templateType}{presentation}{
    % Load the document class, load packages, and flag the template as loaded
    \LoadClass{beamer}
    \RequirePackage{appendixnumberbeamer}
    \RequirePackage{comment}
    \loadPackagesSharedByAll
    \toggletrue{TemplateTypeLoaded}
    % Load theme, font, and beamer template
    \usetheme{Madrid}
    \usecolortheme[named=PrincetonOrange]{structure}
    \usefonttheme{serif}
    \setbeamertemplate{blocks}[rounded]
    \setbeamertemplate{navigation symbols}{}
    \setbeamertemplate{footline}[frame number]
    \titlegraphic{\includegraphics[scale=0.07]{./logo.png}}
    % Define footnote size.
    \renewcommand{\footnotesize}{\tiny}
    % Define animations and first-section toggles
    \newtoggle{allowAnimations}
    \toggletrue{allowAnimations}
    \newtoggle{firstSectionHasNotBeenCalled}
    \toggletrue{firstSectionHasNotBeenCalled}
    % Define command that generates the front matter.
    \newcommand{\firstOutline}{
        \begin{frame}{Outline}
            \tableofcontents
        \end{frame}
    }
    \newcommand{\titleAndOutline}{
        \frame{\titlepage}
        \firstOutline
    }
    \newcommand{\genFront}[3]{
        \title{#1}
        \author{#2}
        \date{#3}
        \titleAndOutline
    }
    % Define command that generates a section.
    \newcommand{\ro}{
        \begin{frame}{Outline}
            \tableofcontents[currentsection]
        \end{frame}
    }
    \newcommand{\genPart}[1]{
        \iftoggle{firstSectionHasNotBeenCalled}{
            \newcommand{\SectionName}{#1}
            \togglefalse{firstSectionHasNotBeenCalled}
        }{
            \renewcommand{\SectionName}{#1}
        }
        \section{#1}
        \ro
    }
    % Define command that generates a frame.
    \newcommand{\genSubPart}[3][true]{
        \iftoggle{allowAnimations}{
            \ifbool{#1}{
                \begin{frame}{#2}{\SectionName}
                    % Make empty frame
                \end{frame}
                \addtocounter{framenumber}{-1}
            }{
                % Do nothing
            }
        }{
            % Do nothing
        }
        \begin{frame}{#2}{\SectionName}
            #3
        \end{frame}
    }
    % Define animation-capable environments for enumerations and itemizations.
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
    % Define command that generates the appendix.
    \renewcommand\appendixname{Appendix}
}{
    % Do nothing
}

% NOTE:
\ifdefstring{\templateType}{note}{
    \loadPackagesSharedByAll
    \loadPackagesSharedByDocs
    \toggletrue{TemplateTypeLoaded}
    % Do something
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
