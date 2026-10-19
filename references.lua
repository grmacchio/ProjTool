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
    return value and value:gsub("[%s{}]", "") ~= ""
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
        if parent and entries[parent] then
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

local function validate(key, record)
    local f = record.fields
    local missing = {}
    local function require_field(label, ...)
        for _, field in ipairs({...}) do
            if nonempty(f[field]) then return end
        end
        missing[#missing + 1] = label
    end
    local function year()
        require_field("year (or date)", "year", "date")
    end
    local function journal()
        require_field("journal (abbreviated) or journaltitle", "journal", "journaltitle")
        if f.pubstate ~= "submitted" and f.pubstate ~= "inpress" then
            year()
            require_field("volume", "volume")
            require_field("pages or eid", "pages", "eid")
        end
    end
    require_field("title", "title")
    if record.kind == "book" then
        require_field("author or editor", "author", "editor")
    else
        require_field("author", "author")
    end
    if record.kind == "article" then
        journal()
    elseif record.kind == "book" then
        year()
        require_field("publisher", "publisher")
        require_field("address (publisher location)", "address", "location")
    elseif record.kind == "phdthesis" then
        year()
        require_field("school or institution", "school", "institution")
        require_field("address (university location)", "address", "location")
    elseif record.kind == "inproceedings" then
        if f.entrysubtype == "journal" or nonempty(f.journal) or nonempty(f.journaltitle) then
            journal()
        else
            year()
            require_field("booktitle", "booktitle")
            if f.entrysubtype == "book" then
                require_field("publisher", "publisher")
                require_field("address (publisher location)", "address", "location")
                require_field("pages", "pages")
            else
                require_field("publisher or organization", "publisher", "organization")
            end
        end
    elseif record.kind == "misc" then
        local online = nonempty(f.url) or nonempty(f.doi) or nonempty(f.eprint)
        local manuscript = (f.howpublished or ""):lower() == "manuscript"
        if not online then
            year()
            if not manuscript then
                require_field("institution (or organization) for an institutional preprint; otherwise url, doi, or eprint", "institution", "organization")
                require_field("address (institution location)", "address", "location")
            end
        end
    else
        error("Unsupported reference type @" .. record.kind .. " in " .. record.path, 0)
    end
    if #missing > 0 then
        error("Reference " .. key .. " (@" .. record.kind .. ") in " .. record.path ..
            " is missing: " .. table.concat(missing, "; "), 0)
    end
end

local function inlines(text)
    if not nonempty(text) then return nil end
    local doc = pandoc.read(text, "latex")
    if doc.blocks[1] and doc.blocks[1].content then
        return pandoc.MetaInlines(doc.blocks[1].content)
    end
    return pandoc.MetaString(text)
end

local journal_abbreviations = {
    ["Journal of Tests"] = "J. Test.",
    ["Journal of Test Examples"] = "J. Test Ex.",
    ["Journal of Conference Tests"] = "J. Conf. Test."
}
local series_abbreviations = {
    ["Test Series"] = "Test Ser.",
    ["Conference Series"] = "Conf. Ser."
}
local publisher_abbreviations = {
    ["Society for Industrial and Applied Mathematics"] = "SIAM"
}
local archive_abbreviations = {
    ["Social Science Research Network"] = "SSRN"
}

local function normalize(ref, record)
    local f = record.fields
    local kind = record.kind
    if kind == "book" or kind == "misc" or kind == "phdthesis" then
        ref.title = inlines(f.title)
    end
    if kind == "inproceedings" then
        if f.entrysubtype == "journal" or nonempty(f.journal) or nonempty(f.journaltitle) then
            ref["event-title"] = inlines(f.booktitle or "Conference")
            ref["container-title"] = inlines(f.journaltitle or f.journal)
        else
            ref["container-title"] = inlines(f.booktitle)
            if f.entrysubtype == "book" then
                ref.type = pandoc.MetaString("chapter")
            end
        end
    end
    ref["container-title-short"] = inlines(f.shortjournal or journal_abbreviations[f.journaltitle or f.journal])
    ref["collection-title"] = inlines(series_abbreviations[f.series] or f.series)
    if kind == "book" and publisher_abbreviations[f.publisher] then
        ref.publisher = inlines(publisher_abbreviations[f.publisher])
    end
    if nonempty(f.series) then
        ref.volume = inlines(f.volume or f.number)
    end
    if kind == "inproceedings" and not ref["event-title"] then
        local publisher = {}
        if nonempty(f.organization) and f.entrysubtype ~= "book" then
            publisher[#publisher + 1] = f.organization
        end
        if nonempty(f.publisher) then publisher[#publisher + 1] = publisher_abbreviations[f.publisher] or f.publisher end
        ref.publisher = inlines(table.concat(publisher, ", "))
    end
    if kind == "article" or (kind == "inproceedings" and ref["event-title"]) then
        ref.number = inlines(f.eid)
        ref["number-of-pages"] = nil
        if nonempty(f.eid) and nonempty(f.pagetotal) then
            local count = tonumber((f.pagetotal:gsub("[{}%s]", "")))
            ref["number-of-pages"] = inlines(f.pagetotal .. (count == 1 and " page" or " pages"))
        end
        ref.status = nil
        if f.pubstate == "submitted" or f.pubstate == "inpress" then
            ref.status = pandoc.MetaString(f.pubstate == "inpress" and "to appear" or "submitted")
        end
    end
    if kind == "misc" then
        ref.genre = inlines(f.howpublished or "preprint")
        ref.publisher = inlines(f.institution or f.organization)
        ref["publisher-place"] = inlines(f.location or f.address)
        ref.number = inlines(f.number)
    elseif kind == "phdthesis" then
        ref.genre = inlines(f.type or "PhD thesis")
    end
    if nonempty(f.eprint) and not nonempty(f.url) then
        local archive = f.eprinttype or f.archiveprefix or ""
        archive = archive_abbreviations[archive] or archive
        if archive:lower() == "arxiv" then
            ref.URL = pandoc.MetaString("https://arxiv.org/abs/" .. f.eprint)
        else
            ref.URL = nil
            ref.archive = inlines(archive)
            ref.archive_location = inlines(f.eprint)
        end
    end
    ref.note = nil
    return ref
end

local function prepare_references(doc)
    if not doc.meta.bibliography then return doc end
    local bibliography = doc.meta.bibliography
    if pandoc.utils.type(bibliography) ~= "List" and
        pandoc.utils.type(bibliography) ~= "MetaList" and
        type(bibliography[1]) == "nil" then
        bibliography = {bibliography}
    end
    local paths = {}
    for _, path in ipairs(bibliography) do
        paths[#paths + 1] = pandoc.utils.stringify(path)
    end
    local entries = read_entries(paths)
    for key, record in pairs(entries) do validate(key, record) end
    local refs = pandoc.utils.references(doc)
    for _, ref in ipairs(refs) do
        local key = pandoc.utils.stringify(ref.id)
        local record = entries[key]
        if not record then error("Missing bibliography data for " .. key, 0) end
        normalize(ref, record)
    end
    doc.meta.references = pandoc.MetaList(refs)
    doc.meta.bibliography = nil
    return doc
end

local function rendered_references(document)
    local references = {}
    document:walk({
        Div = function(div)
            local key = div.identifier:match("^ref%-(.+)$")
            if not key then return end
            div:walk({
                Span = function(span)
                    if span.classes:includes("csl-right-inline") then
                        local formatted = pandoc.Pandoc({
                            pandoc.Plain(span.content)
                        }):walk({
                            SmallCaps = function(names)
                                return pandoc.Span(names.content, pandoc.Attr(
                                    "", {}, {style = "font-variant: small-caps;"}))
                            end
                        })
                        references[key] = pandoc.write(formatted,
                            "html", {wrap_text = "none"}):gsub("%s+$", "")
                    end
                end
            })
        end
    })
    return references
end

local function starts_section(block)
    return block and block.t == "Header" and block.level <= 3
end

local function format_presentation_references(document)
    if pandoc.utils.stringify(document.meta["template-type"] or "") ~= "presentation" then
        return document
    end
    local references = rendered_references(document)
    local output = pandoc.Blocks({})
    local keys = {}
    local numbers = {}

    local function emit_references()
        if #keys == 0 then return end
        local html = {
            '<div class="presentation-footnotes">',
            '<hr style="width: 40%; margin: 1em 0 0.5em;">'
        }
        for number, key in ipairs(keys) do
            html[#html + 1] = '<p style="margin: 0.35em 0;"><small style="' ..
                'display: block; font-size: 75%; line-height: 1.35; ' ..
                'padding-left: 1.8em; text-indent: -1.8em;">' ..
                '<span style="display: inline-block; width: 1.8em; ' ..
                'text-align: right; text-indent: 0;"><sup>' .. number ..
                '</sup></span>' .. references[key] .. '</small></p>'
        end
        html[#html + 1] = '</div>'
        output:insert(pandoc.RawBlock("html", table.concat(html, "\n")))
        keys = {}
        numbers = {}
    end

    local function citation(cite)
        local labels = {}
        for _, item in ipairs(cite.citations) do
            local key = item.id
            if not references[key] then
                error("Missing formatted presentation reference: " .. key, 0)
            end
            if not numbers[key] then
                keys[#keys + 1] = key
                numbers[key] = #keys
            end
            labels[#labels + 1] = tostring(numbers[key])
        end
        return pandoc.Superscript({pandoc.Str(table.concat(labels, ","))})
    end

    for index, block in ipairs(document.blocks) do
        local section_anchor = block.t == "RawBlock" and
            block.format == "html" and block.text:match('^<a id="[^"]+"></a>$') and
            starts_section(document.blocks[index + 1])
        if starts_section(block) or section_anchor then
            emit_references()
        end
        if not (block.t == "Div" and block.identifier == "refs") then
            output:insert(block:walk({Cite = citation}))
        end
    end
    emit_references()
    document.blocks = output
    return document
end

function Pandoc(document)
    document = prepare_references(document)
    if document.meta.csl then
        document = pandoc.utils.citeproc(document)
    end
    return format_presentation_references(document)
end
