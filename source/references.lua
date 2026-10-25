local P, R, S, V = lpeg.P, lpeg.R, lpeg.S, lpeg.V
local C, Ct, Cp = lpeg.C, lpeg.Ct, lpeg.Cp
local space = (S(" \t\r\n") + P("%") * (1 - S("\r\n"))^0)^0
local escaped = P("\\") * P(1)
local braced = P { P("{") * (escaped + (1 - S("{}\\")) + V(1))^0 * P("}") }
local quoted = P('"') * (escaped + braced + (1 - S('"\\"')))^0 * P('"')
local name = (R("az", "AZ", "09") + S("_-:"))^1
local literal = (C(braced) + C(quoted)) / function(value)
    return { literal = value:sub(2, -2) }
end
local token = C((1 - S(" \t\r\n,#})"))^1) / function(value)
    return { token = value }
end
local value = Ct((literal + token) * (space * P("#") * space * (literal + token))^0)
local fields = Ct((space * Ct(C(name) * space * P("=") * space * value) *
    space * (P(",") + -P(1)))^0) * space * -P(1)
local body = P("{") * C((braced + quoted + (1 - S('{}"')))^0) * P("}") +
    P("(") * C((braced + quoted + (1 - S('()"')))^0) * P(")")
local entry = Ct(P("@") * C(R("az", "AZ")^1) * space * body) * Cp()
local entry_start = P("@") * R("az", "AZ")^1 * space * S("{(")
local next_entry = (P("%") * (1 - S("\r\n"))^0 + (1 - entry_start))^0 * Cp() * #entry_start

local function nonempty(value)
    return value and value:gsub("[%s{}]", "") ~= "" and not value:match("^%s*<[^>]+>%s*$")
end

local function read_entries(paths)
    local entries = {}
    local macros = {
        jan = "January", feb = "February", mar = "March", apr = "April",
        may = "May", jun = "June", jul = "July", aug = "August",
        sep = "September", oct = "October", nov = "November", dec = "December"
    }
    for _, path in ipairs(paths) do
        local file = assert(io.open(path, "r"))
        local source = file:read("*a")
        file:close()
        local position = 1
        while true do
            local start = lpeg.match(next_entry, source, position)
            if not start then break end
            local record, finish = lpeg.match(entry, source, start)
            if not record then error("Cannot parse bibliography: " .. path, 0) end
            position = finish
            local kind = record[1]:lower()
            if kind ~= "comment" and kind ~= "preamble" then
                local key, contents
                if kind == "string" then
                    contents = record[2]
                else
                    key, contents = record[2]:match("^%s*([^,%s]+)%s*,(.*)$")
                    if not key then error("Missing reference key in " .. path, 0) end
                end
                local parsed = lpeg.match(fields, contents)
                if not parsed then error("Cannot parse reference " .. (key or "@string") .. " in " .. path, 0) end
                local data = {}
                for _, field in ipairs(parsed) do
                    local parts = {}
                    for _, part in ipairs(field[2]) do
                        parts[#parts + 1] = part.literal or macros[part.token:lower()] or part.token
                    end
                    data[field[1]:lower()] = table.concat(parts)
                end
                if kind == "string" then
                    for field, text in pairs(data) do macros[field] = text end
                else
                    if entries[key] then error("Duplicate reference key: " .. key, 0) end
                    entries[key] = { kind = kind, fields = data, path = path }
                end
            end
        end
    end
    local function inherit(key, visiting)
        local record = entries[key]
        if not record then return end
        if visiting[key] then error("Circular reference inheritance: " .. key, 0) end
        local parent = record.fields.crossref
        if parent and not entries[parent] then
            error("Missing cross-reference " .. parent .. " in " .. record.path, 0)
        end
        if parent then
            visiting[key] = true
            inherit(parent, visiting)
            for field, text in pairs(entries[parent].fields) do
                if record.fields[field] == nil then record.fields[field] = text end
            end
            visiting[key] = nil
        end
    end
    for key in pairs(entries) do inherit(key, {}) end
    return entries
end


local supported = {
    article = true, book = true, booklet = true, inbook = true,
    incollection = true, inproceedings = true, conference = true,
    manual = true, mastersthesis = true, phdthesis = true,
    bachelorsthesis = true, misc = true, proceedings = true,
    techreport = true, unpublished = true, periodical = true
}

local function validate(key, record)
    local f, kind = record.fields, record.kind
    if not supported[kind] then
        error("Unsupported reference type @" .. kind .. " in " .. record.path, 0)
    end
    local missing = {}
    local function need(label, ...)
        for _, name in ipairs({...}) do
            if nonempty(f[name]) then return end
        end
        missing[#missing + 1] = label
    end
    local function year() need("year or date", "year", "date") end
    local function location() need("address or location", "address", "location") end
    local function journal()
        need("journal or journaltitle", "journal", "journaltitle")
        if f.pubstate ~= "submitted" and f.pubstate ~= "inpress" then
            year()
        end
    end
    need("title", "title")
    if kind == "book" or kind == "inbook" or kind == "periodical" then
        need("author or editor", "author", "editor")
    elseif kind == "proceedings" or kind == "manual" then
        need("author, editor, or organization", "author", "editor", "organization")
    elseif kind ~= "booklet" and kind ~= "misc" then
        need("author", "author")
    end
    if kind == "article" then
        journal()
    elseif kind == "book" or kind == "inbook" or kind == "incollection" then
        need("publisher", "publisher")
        if f.pubstate ~= "inpress" then
            year()
            location()
        end
        if kind == "inbook" then need("chapter or pages", "chapter", "pages") end
        if kind == "incollection" then
            need("booktitle", "booktitle")
        end
    elseif kind:match("thesis$") then
        year()
        need("school or institution", "school", "institution")
        location()
    elseif kind == "inproceedings" or kind == "conference" then
        if nonempty(f.journal) or nonempty(f.journaltitle) then
            journal()
        else
            year()
            need("booktitle", "booktitle")
            need("publisher or organization", "publisher", "organization")
            if f.entrysubtype == "book" then
                location()
            end
        end
    elseif kind == "techreport" then
        year()
        need("institution", "institution")
        location()
    elseif kind == "unpublished" then
        need("note", "note")
    elseif kind == "periodical" then
        year()
        need("volume", "volume")
        need("number", "number")
    elseif kind == "proceedings" then
        year()
    elseif kind == "misc" then
        need("author, editor, organization, or institution", "author", "editor", "organization", "institution")
        need("publication description or locator", "howpublished", "note", "url", "doi", "eprint", "institution", "organization")
    end
    if #missing > 0 then
        error("Reference " .. key .. " (@" .. kind .. ") in " .. record.path ..
            " is missing: " .. table.concat(missing, "; "), 0)
    end
end

local function read_file(path)
    local file = assert(io.open(path, "r"))
    local value = file:read("*a")
    file:close()
    return value
end

local function write_file(path, value, mode)
    local file = assert(io.open(path, mode or "w"))
    file:write(value)
    file:close()
end

local function ordinal(value)
    local number = tonumber(value)
    if not number then return value end
    local last, tens = number % 10, number % 100
    local suffix = "th"
    if tens < 11 or tens > 13 then
        suffix = ({[1] = "st", [2] = "nd", [3] = "rd"})[last] or suffix
    end
    return tostring(number) .. suffix
end

local journal_abbreviations = {
    ["Mathematics of Computation"] = "Math. Comp.",
    ["Journal d'Analyse Mathématique"] = "J. Anal. Math.",
    ["Advances in Pure and Applied Mathematics"] = "Adv. Pure Appl. Math.",
    ["Applied Mathematics Letters"] = "Appl. Math. Lett.",
    ["Computers \\& Mathematics with Applications"] = "Comput. Math. Appl.",
    ["Journal of Siberian Federal University. Mathematics \\& Physics"] = "J. Sib. Fed. Univ. Math. Phys.",
    ["Machine Learning: Science and Technology"] = "Mach. Learn.: Sci. Technol.",
    ["Nonlinear Dynamics"] = "Nonlinear Dyn.",
    ["ACM Transactions on Mathematical Software"] = "ACM Trans. Math. Software",
    ["Acta Applicandae Mathematicae"] = "Acta Appl. Math.",
    ["Acta Mathematica"] = "Acta Math.",
    ["Acta Numerica"] = "Acta Numer.",
    ["Advances in Computational Mathematics"] = "Adv. Comput. Math.",
    ["Advances in Differential Equations"] = "Adv. Differential Equations",
    ["Annals of Mathematics"] = "Ann. of Math. (2)",
    ["Annual Review of Fluid Mechanics"] = "Annu. Rev. Fluid Mech.",
    ["Annual Review of Statistics and Its Application"] = "Annu. Rev. Stat. Appl.",
    ["Applied Categorical Structures"] = "Appl. Categ. Structures",
    ["Applied and Computational Harmonic Analysis"] = "Appl. Comput. Harmon. Anal.",
    ["Automatica"] = "Automatica J. IFAC",
    ["Chaos: An Interdisciplinary Journal of Nonlinear Science"] = "Chaos",
    ["Communications in Mathematical Physics"] = "Comm. Math. Phys.",
    ["Communications in Nonlinear Science and Numerical Simulation"] = "Commun. Nonlinear Sci. Numer. Simul.",
    ["Communications in Theoretical Physics"] = "Commun. Theor. Phys. (Beijing)",
    ["Communications on Pure and Applied Mathematics"] = "Comm. Pure Appl. Math.",
    ["Comptes Rendus. Mathématique"] = "C. R. Math. Acad. Sci. Paris",
    ["Computer Methods in Applied Mechanics and Engineering"] = "Comput. Methods Appl. Mech. Engrg.",
    ["Czechoslovak Mathematical Journal"] = "Czechoslovak Math. J.",
    ["Discrete and Continuous Dynamical Systems"] = "Discrete Contin. Dyn. Syst.",
    ["Dynamical Systems"] = "Dyn. Syst.",
    ["ESAIM: Mathematical Modelling and Numerical Analysis"] = "ESAIM Math. Model. Numer. Anal.",
    ["Ergodic Theory and Dynamical Systems"] = "Ergodic Theory Dynam. Systems",
    ["Forum of Mathematics, Pi"] = "Forum Math. Pi",
    ["Hiroshima Mathematical Journal"] = "Hiroshima Math. J.",
    ["IEEE Control Systems Letters"] = "IEEE Control Syst. Lett.",
    ["IEEE Transactions on Automatic Control"] = "IEEE Trans. Automat. Control",
    ["IFAC-PapersOnLine"] = "IFAC-PapersOnLine",
    ["Indian Journal of Pure and Applied Mathematics"] = "Indian J. Pure Appl. Math.",
    ["Indiana University Mathematics Journal"] = "Indiana Univ. Math. J.",
    ["International Journal for Numerical Methods in Engineering"] = "Internat. J. Numer. Methods Engrg.",
    ["International Journal of Bifurcation and Chaos"] = "Internat. J. Bifur. Chaos Appl. Sci. Engrg.",
    ["International Journal of Control"] = "Internat. J. Control",
    ["International Journal of Mathematics and Mathematical Sciences"] = "Int. J. Math. Math. Sci.",
    ["International Journal of Robust and Nonlinear Control"] = "Internat. J. Robust Nonlinear Control",
    ["International Journal of Systems Science"] = "Internat. J. Systems Sci.",
    ["Journal de Mathématiques Pures et Appliquées"] = "J. Math. Pures Appl. (9)",
    ["Journal of Applied Mathematics and Computing"] = "J. Appl. Math. Comput.",
    ["Journal of Computational Physics"] = "J. Comput. Phys.",
    ["Journal of Conference Tests"] = "J. Conf. Test.",
    ["Journal of Differential Equations"] = "J. Differential Equations",
    ["Journal of Dynamical Systems and Geometric Theories"] = "J. Dyn. Syst. Geom. Theor.",
    ["Journal of Dynamics and Differential Equations"] = "J. Dynam. Differential Equations",
    ["Journal of Fluid Mechanics"] = "J. Fluid Mech.",
    ["Journal of Machine Learning Research"] = "J. Mach. Learn. Res.",
    ["Journal of Mathematical Analysis and Applications"] = "J. Math. Anal. Appl.",
    ["Journal of Mathematical Physics"] = "J. Math. Phys.",
    ["Journal of Mathematical Psychology"] = "J. Math. Psych.",
    ["Journal of Nonlinear Science"] = "J. Nonlinear Sci.",
    ["Journal of Scientific Computing"] = "J. Sci. Comput.",
    ["Journal of Statistical Physics"] = "J. Stat. Phys.",
    ["Journal of Systems Science and Complexity"] = "J. Syst. Sci. Complex.",
    ["Journal of Test Examples"] = "J. Test Ex.",
    ["Journal of Tests"] = "J. Test.",
    ["Journal of The Korean Mathematical Society"] = "J. Korean Math. Soc.",
    ["Journal of the ACM"] = "J. ACM",
    ["Journal of the American Mathematical Society"] = "J. Amer. Math. Soc.",
    ["Journal of the Korean Mathematical Society"] = "J. Korean Math. Soc.",
    ["Linear Algebra and its Applications"] = "Linear Algebra Appl.",
    ["Linear and Multilinear Algebra"] = "Linear Multilinear Algebra",
    ["Mathematical Modelling of Natural Phenomena"] = "Math. Model. Nat. Phenom.",
    ["Mathematics of Control, Signals, and Systems"] = "Math. Control Signals Systems",
    ["Memoirs of the American Mathematical Society"] = "Mem. Amer. Math. Soc.",
    ["Multiscale Modeling \\& Simulation"] = "Multiscale Model. Simul.",
    ["Neural Computation"] = "Neural Comput.",
    ["New Journal of Physics"] = "New J. Phys.",
    ["New York Journal of Mathematics"] = "New York J. Math.",
    ["Nonlinear Analysis"] = "Nonlinear Anal.",
    ["Nonlinear Analysis: Theory, Methods \\& Applications"] = "Nonlinear Anal.",
    ["Nonlinearity"] = "Nonlinearity",
    ["Numerical Functional Analysis and Optimization"] = "Numer. Funct. Anal. Optim.",
    ["Numerische Mathematik"] = "Numer. Math.",
    ["Physica D: Nonlinear Phenomena"] = "Phys. D",
    ["Physical Review A"] = "Phys. Rev. A",
    ["Physical Review E"] = "Phys. Rev. E",
    ["Physical Review Letters"] = "Phys. Rev. Lett.",
    ["Physics Letters A"] = "Phys. Lett. A",
    ["Physics Reports"] = "Phys. Rep.",
    ["Poincare Journal of Analysis and Applications"] = "Poincare J. Anal. Appl.",
    ["Proceedings of the American Mathematical Society"] = "Proc. Amer. Math. Soc.",
    ["Proceedings of the National Academy of Sciences"] = "Proc. Natl. Acad. Sci. USA",
    ["Proceedings of the Royal Society of Edinburgh: Section A Mathematics"] = "Proc. Roy. Soc. Edinburgh Sect. A",
    ["Publications Mathématiques de l'Institut des Hautes Études Scientifiques"] = "Publ. Math. Inst. Hautes Etudes Sci.",
    ["Qualitative Theory of Dynamical Systems"] = "Qual. Theory Dyn. Syst.",
    ["Quarterly of Applied Mathematics"] = "Quart. Appl. Math.",
    ["Reviews of Modern Physics"] = "Rev. Modern Phys.",
    ["Revista de la Real Academia de Ciencias Exactas, Físicas y Naturales. Serie A. Matemáticas"] = "Rev. R. Acad. Cienc. Exactas Fis. Nat. Ser. A Mat. RACSAM",
    ["Russian Mathematical Surveys"] = "Russian Math. Surveys",
    ["SIAM Journal on Applied Algebra and Geometry"] = "SIAM J. Appl. Algebra Geom.",
    ["SIAM Journal on Applied Dynamical Systems"] = "SIAM J. Appl. Dyn. Syst.",
    ["SIAM Journal on Applied Mathematics"] = "SIAM J. Appl. Math.",
    ["SIAM Journal on Control and Optimization"] = "SIAM J. Control Optim.",
    ["SIAM Journal on Mathematical Analysis"] = "SIAM J. Math. Anal.",
    ["SIAM Journal on Matrix Analysis and Applications"] = "SIAM J. Matrix Anal. Appl.",
    ["SIAM Journal on Numerical Analysis"] = "SIAM J. Numer. Anal.",
    ["SIAM Journal on Scientific Computing"] = "SIAM J. Sci. Comput.",
    ["SIAM News"] = "SIAM News",
    ["SIAM Review"] = "SIAM Rev.",
    ["SIAM/ASA Journal on Uncertainty Quantification"] = "SIAM/ASA J. Uncertain. Quantif.",
    ["Selecta Mathematica"] = "Selecta Math. (N.S.)",
    ["Set-Valued and Variational Analysis"] = "Set-Valued Var. Anal.",
    ["Systems \\& Control Letters"] = "Systems Control Lett.",
    ["The American Mathematical Monthly"] = "Amer. Math. Monthly",
    ["The Mathematical Intelligencer"] = "Math. Intelligencer",
    ["Theoretical and Computational Fluid Dynamics"] = "Theor. Comput. Fluid Dyn.",
    ["Topology and its Applications"] = "Topology Appl.",
    ["Transactions of the American Mathematical Society"] = "Trans. Amer. Math. Soc.",
    ["ZAMP Zeitschrift für angewandte Mathematik und Physik"] = "Z. Angew. Math. Phys.",
    ["Zeitschrift für angewandte Mathematik und Physik"] = "Z. Angew. Math. Phys."
}

local function journal_name(value)
    return value and (journal_abbreviations[value:gsub("[{}]", "")] or value)
end

local function normalize(record)
    local f, kind = {}, record.kind
    for name, value in pairs(record.fields) do f[name] = value end
    f.year = f.year or (f.date or ""):match("^(%d%d%d%d)")
    f.address = f.address or f.location
    f.journal = f.shortjournal or journal_name(f.journal or f.journaltitle)
    f.school = f.school or f.institution
    local publishers = {
        ["Society for Industrial and Applied Mathematics"] = "SIAM",
        ["Institute of Electrical and Electronics Engineers"] = "IEEE",
        ["Proceedings of Machine Learning Research"] = "PMLR"
    }
    f.publisher = publishers[f.publisher] or f.publisher
    f.crossref = nil
    if f.edition then f.edition = ordinal(f.edition) end
    if f.doi then f.doi = f.doi:gsub("^https?://[dx%.]*doi%.org/", "") end
    if f.url and f.doi and f.url:lower():gsub("^https?://[dx%.]*doi%.org/", "") == f.doi:lower() then
        f.url = nil
    end
    if f.eprint and f.url and f.url:match("arxiv%.org/abs/" .. f.eprint:gsub("%.", "%%.") .. "$") then
        f.url = nil
    end
    if f.eprint and not f.archive then
        local archive = (f.eprinttype or f.archiveprefix or "arxiv"):lower()
        if archive == "ssrn" or archive == "social science research network" then
            f.url = f.url or ("https://papers.ssrn.com/sol3/papers.cfm?abstract_id=" .. f.eprint)
            f.eprint = nil
        elseif archive ~= "arxiv" then
            if not f.url then error("Non-arXiv eprints require a url or archive URL", 0) end
            f.eprint = nil
        end
    end
    if kind == "bachelorsthesis" then
        kind = "mastersthesis"
        f.type = f.type or "Bachelor's thesis"
    elseif kind == "inproceedings" or kind == "conference" then
        if nonempty(f.journal) then
            kind = "article"
        elseif f.entrysubtype == "book" then
            kind = "incollection"
        end
    elseif kind == "periodical" then
        f.journal = f.shortjournal or journal_name(f.title)
        f.title = f.issuetitle or f.title
    elseif kind == "misc" then
        local description = {}
        for _, name in ipairs({"howpublished", "number", "institution", "organization", "address"}) do
            if nonempty(f[name]) then description[#description + 1] = f[name] end
        end
        if #description > 0 then f.howpublished = table.concat(description, ", ") end
        if not nonempty(f.author) and nonempty(f.editor) then
            f.author = f.editor
        elseif not nonempty(f.author) then
            f.author = "{" .. (f.organization or f.institution) .. "}"
        end
    end
    for _, name in ipairs({"doi", "url", "archive", "eprint"}) do
        if f[name] then
            f[name] = f[name]:gsub("([^\\])([%%#])", "%1\\%2"):gsub("^([%%#])", "\\%1")
        end
    end
    if kind ~= "article" and f.pubstate == "inpress" then
        f.note = nonempty(f.note) and (f.note .. "; to appear") or "To appear"
        f.pubstate = nil
    elseif f.pubstate == "inpress" then
        f.pubstate = "to appear"
    elseif f.pubstate ~= "submitted" then
        f.pubstate = nil
    end
    return kind, f
end

local translation_style = [[
FUNCTION {format.translation}
{ translator empty$
    { origdate empty$
        { "" }
        { "Originally published in " origdate * }
      if$
    }
    { "Translated by " translator format.names *
      origdate empty$
        'skip$
        { " from the " * origdate * " original" * }
      if$
    }
  if$
}
]]

local periodical_style = [[
FUNCTION {periodical}
{ output.bibitem
  author empty$
    { format.editors "editor" output.check }
    { format.authors output.nonnull }
  if$
  format.btitle "title" output.check
  journal "journal" output.check
  volume field.or.null
  number empty$
    'skip$
    { "(" * number * ")" * }
  if$
  year empty$
    { "empty year in " cite$ * warning$ }
    { " (" * year * ")" * }
  if$
  output
  format.doi output
  format.url output
  format.eprint output
  new.block
  note output
  fin.entry
}
]]

local function format_entries(entries)
    local source_dir = pandoc.path.directory(PANDOC_SCRIPT_FILE)
    local style = read_file(pandoc.path.join({source_dir, "siamplain.bst"}))
    style = style:gsub("{ address", "{ pubstate\n    translator\n    origdate\n    address", 1)
    style = style:gsub("\nFUNCTION {book}\n(.-)\nFUNCTION {booklet}", function(book)
        book = book:gsub("  note output", "  format.translation output\n  new.block\n  note output", 1)
        return "\n" .. translation_style .. "\nFUNCTION {book}\n" .. book .. "\nFUNCTION {booklet}"
    end, 1)
    style = style:gsub("format%.vol%.year output", 'pubstate empty$ { format.vol.year output } { pubstate output } if$', 1)
    style = style:gsub('{ pagetotal "~pages" %* }',
        '{ pagetotal duplicate$ "1" = { "~page" } { "~pages" } if$ * }', 1)
    style = style:gsub("\nREAD\n", "\n" .. periodical_style .. "\nREAD\n", 1)
    style = style:gsub('type%$ "inbook" =\n  or', 'type$ "inbook" =\n  or\n  type$ "periodical" =\n  or', 1)
    local keys, bibliography = {}, {}
    for key in pairs(entries) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local kind, fields = normalize(entries[key])
        local names, values = {}, {}
        for name in pairs(fields) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            values[#values + 1] = "  " .. name .. " = {" .. fields[name] .. "}"
        end
        bibliography[#bibliography + 1] = "@" .. kind .. "{" .. key .. ",\n" ..
            table.concat(values, ",\n") .. "\n}\n"
    end
    local bbl = pandoc.system.with_temporary_directory("projtool-references", function(directory)
        return pandoc.system.with_working_directory(directory, function()
            write_file("siamplain.bst", style)
            write_file("references.bib", table.concat(bibliography, "\n"))
            write_file("references.aux", "\\relax\n\\citation{*}\n\\bibstyle{siamplain}\n\\bibdata{references}\n")
            local ok, output = pcall(pandoc.pipe, "bibtexu", {"references"}, "")
            local report = tostring(output)
            if not ok and not report:match("error code 1%)") then
                error("SIAM bibliography build failed:\n" .. report, 0)
            end
            for warning in report:gmatch("Warning%-%-([^\r\n]+)") do
                io.stderr:write("SIAM bibliography warning: " .. warning .. "\n")
            end
            return read_file("references.bbl")
        end)
    end)
    local result, order = {}, {}
    local matches = {}
    for start, key, finish in bbl:gmatch("()\\bibitem{([^}]+)}()") do
        matches[#matches + 1] = {start = start, key = key, finish = finish}
    end
    local ending = assert(bbl:find("\\end{thebibliography}", 1, true))
    for index, match in ipairs(matches) do
        local stop = matches[index + 1] and matches[index + 1].start or ending
        local latex = bbl:sub(match.finish, stop - 1):gsub("^%s+", ""):gsub("%s+$", "")
        local markdown_latex = latex:gsub("\\newblock%s*", " "):gsub("\\sc%s+", "\\scshape ")
        local document = pandoc.read(markdown_latex, "latex"):walk({
            SmallCaps = function(names)
                return pandoc.Span(names.content, pandoc.Attr("", {}, {style = "font-variant: small-caps;"}))
            end
        })
        local inline = pandoc.Inlines({})
        for _, block in ipairs(document.blocks) do
            if #inline > 0 then inline:insert(pandoc.Space()) end
            if block.content then inline:extend(block.content) end
        end
        result[match.key] = {number = index, latex = latex,
            html = pandoc.write(pandoc.Pandoc({pandoc.Plain(inline)}), "html", {wrap_text = "none"}):gsub("%s+$", "")}
        order[#order + 1] = match.key
    end
    assert(#order == #keys, "Incomplete SIAM bibliography")
    return result, order, bbl
end

local function bibliography_paths(document)
    local bibliography = document.meta.bibliography
    if not bibliography then return {} end
    if pandoc.utils.type(bibliography) ~= "List" and
        pandoc.utils.type(bibliography) ~= "MetaList" and
        type(bibliography[1]) == "nil" then bibliography = {bibliography} end
    local paths = {}
    for _, path in ipairs(bibliography) do paths[#paths + 1] = pandoc.utils.stringify(path) end
    return paths
end

local function starts_section(block)
    return block and block.t == "Header" and block.level <= 3
end

local function presentation_references(document, references)
    local output, keys, numbers = pandoc.Blocks({}), {}, {}
    local function emit()
        if #keys == 0 then return end
        local html = {'<div class="presentation-footnotes">',
            '<hr style="width: 40%; margin: 1em 0 0.5em;">'}
        for number, key in ipairs(keys) do
            html[#html + 1] = '<p style="margin: 0.35em 0;"><small style="' ..
                'display: block; font-size: 75%; line-height: 1.35; ' ..
                'padding-left: 1.8em; text-indent: -1.8em;">' ..
                '<span style="display: inline-block; width: 1.8em; ' ..
                'text-align: right; text-indent: 0;"><sup>' .. number ..
                '</sup></span>' .. references[key].html .. '</small></p>'
        end
        html[#html + 1] = '</div>'
        output:insert(pandoc.RawBlock("html", table.concat(html, "\n")))
        keys, numbers = {}, {}
    end
    local function citation(cite)
        local labels = {}
        for _, item in ipairs(cite.citations) do
            assert(references[item.id], "Missing reference: " .. item.id)
            if not numbers[item.id] then
                keys[#keys + 1] = item.id
                numbers[item.id] = #keys
            end
            labels[#labels + 1] = tostring(numbers[item.id])
        end
        return pandoc.Superscript({pandoc.Str(table.concat(labels, ","))})
    end
    for index, block in ipairs(document.blocks) do
        local anchor = block.t == "RawBlock" and block.format == "html" and
            block.text:match('^<a id="[^"]+"></a>$') and starts_section(document.blocks[index + 1])
        if starts_section(block) or anchor then emit() end
        output:insert(block:walk({Cite = citation}))
    end
    emit()
    document.blocks = output
    return document
end

function Pandoc(document)
    local paths = bibliography_paths(document)
    if #paths == 0 then return document end
    local entries = read_entries(paths)
    for key, entry in pairs(entries) do validate(key, entry) end
    if pandoc.utils.stringify(document.meta["reference-check"] or "") == "true" then return document end
    local references, order, bbl = format_entries(entries)
    local output = pandoc.utils.stringify(document.meta["reference-output"] or "")
    if output ~= "" then
        local tex = {}
        for _, key in ipairs(order) do
            tex[#tex + 1] = "\\expandafter\\long\\expandafter\\def\\csname templateReference@" ..
                key .. "\\endcsname{" .. references[key].latex .. "}"
        end
        tex[#tex + 1] = "\\long\\def\\templateBibliography{" .. bbl .. "}"
        write_file(output, table.concat(tex, "\n") .. "\n", "a")
        return document
    end
    document.meta.bibliography, document.meta.csl = nil, nil
    if pandoc.utils.stringify(document.meta["template-type"] or "") == "presentation" then
        return presentation_references(document, references)
    end
    document = document:walk({Cite = function(cite)
        local inline = pandoc.Inlines({pandoc.Str("[")})
        for index, item in ipairs(cite.citations) do
            local ref = assert(references[item.id], "Missing reference: " .. item.id)
            if index > 1 then inline:insert(pandoc.Str(",")); inline:insert(pandoc.Space()) end
            inline:insert(pandoc.Link({pandoc.Str(tostring(ref.number))}, "#ref-" .. item.id))
        end
        inline:insert(pandoc.Str("]"))
        return inline
    end})
    local html = {'<div id="refs" class="references">'}
    for _, key in ipairs(order) do
        local ref = references[key]
        html[#html + 1] = '<div id="ref-' .. key .. '" style="margin: 1em 0; padding-left: 2.5em; text-indent: -2.5em;">' ..
            '<span style="display: inline-block; width: 2.5em; text-indent: 0;">[' ..
            ref.number .. ']</span>' .. ref.html .. '</div>'
    end
    html[#html + 1] = '</div>'
    document.blocks:insert(pandoc.RawBlock("html", table.concat(html, "\n")))
    return document
end
