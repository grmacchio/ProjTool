local function append(collection, value)
    collection[#collection + 1] = value
end

local function extend(collection, values)
    for _, value in ipairs(values) do
        append(collection, value)
    end
end

local function html_escape(value)
    return value:gsub("&", "&amp;"):gsub('"', "&quot;")
        :gsub("<", "&lt;"):gsub(">", "&gt;")
end

function Image(image)
    local source = image.src

    if source:match("^%a[%w+.-]*:") or source:sub(1, 1) == "#" then
        return image
    end

    local file = io.open(source, "rb")
    if not file then
        error("missing image file: " .. source, 0)
    end
    file:close()

    image.src = source:gsub("^%./output/results/", "../../results/")
    return image
end

function Para(paragraph)
    if #paragraph.content ~= 1 or paragraph.content[1].t ~= "Image" then
        return nil
    end

    local image = paragraph.content[1]
    local width = image.attributes and image.attributes.width
    if not width or not width:match("^[%d.]+%%$") then
        return nil
    end

    local source = html_escape(image.src)
    local alt = html_escape(pandoc.utils.stringify(image.caption or {}))
    local html = '<p align="center"><img src="' .. source .. '" alt="' ..
        alt .. '" width="' .. width .. '" style="image-rendering: ' ..
        'pixelated; image-rendering: crisp-edges;"></p>'
    return pandoc.RawBlock("html", html)
end

local function marker_content(block, marker)
    if block.t ~= "Header" and block.t ~= "Para" then
        return nil
    end

    local first = block.content[1]
    if not first or first.t ~= "Strong" or
        pandoc.utils.stringify(first) ~= marker then
        return nil
    end

    local content = {}
    local start = 2
    if block.content[2] and block.content[2].t == "Space" then
        start = 3
    end
    for index = start, #block.content do
        append(content, block.content[index])
    end
    return content
end

local function structured_marker(block, marker, field_count)
    local content = marker_content(block, marker)
    if not content then
        return nil
    end

    local fields = {}
    local index = 1
    for field = 1, field_count do
        while content[index] and content[index].t == "Space" do
            index = index + 1
        end
        local value = content[index]
        if not value or value.t ~= "Strong" then
            error(marker .. " is missing field " .. field, 0)
        end
        fields[field] = pandoc.utils.stringify(value)
        index = index + 1
    end

    while content[index] and content[index].t == "Space" do
        index = index + 1
    end

    local title = {}
    while index <= #content do
        append(title, content[index])
        index = index + 1
    end
    return fields, title
end

local function slug(content)
    local value = pandoc.utils.stringify(content):lower()
    value = value:gsub("[^%w]+", "-")
    value = value:gsub("^%-+", ""):gsub("%-+$", "")
    if value == "" then
        return "item"
    end
    return value
end

local reference_prefixes = {
    thm = "theorem",
    def = "definition",
    fig = "figure",
    part = "chapter",
    subpart = "section",
    proof = "proof-of"
}

function Link(link)
    local kind = link.target:match("^latex%-to%-ref:([%a]+)$")
    if not kind then
        return nil
    end

    local prefix = reference_prefixes[kind]
    if not prefix then
        error("unsupported reference type: " .. kind, 0)
    end
    link.target = "#" .. prefix .. "-" .. slug(link.content)
    return link
end

local function root_mode(value, first, second, command)
    if value ~= first and value ~= second then
        error(command .. " has invalid mode: " .. value, 0)
    end
    return value
end

local function resolved_mode(value, parent, first, second, command)
    if value == "inh" then
        if not parent then
            error(command .. " cannot inherit without a parent", 0)
        end
        return parent
    end
    return root_mode(value, first, second, command)
end

local function anchor(identifier)
    return pandoc.RawBlock("html", '<a id="' .. identifier .. '"></a>')
end

local function strong_label(name, number)
    local content = {pandoc.Str(name)}
    if number then
        append(content, pandoc.Space())
        append(content, pandoc.Str(number))
    end
    return pandoc.Strong(content)
end

local function titled_header(level, name, number, title)
    local content = {}
    extend(content, {
        strong_label(name, number),
        pandoc.Str(":"),
        pandoc.Space()
    })
    extend(content, title)
    return pandoc.Header(level, content)
end

local function object_inlines(name, number, title)
    local content = {
        strong_label(name, number),
        pandoc.Space(),
        pandoc.Str("(")
    }
    extend(content, title)
    append(content, pandoc.Str(")"))
    append(content, pandoc.Strong({pandoc.Str(".")}))
    return content
end

local function centered_figure(number, title, caption)
    local label = "Figure"
    if number then
        label = label .. " " .. number
    end
    local html = '<p align="center"><strong>' .. html_escape(label) ..
        '</strong> (' .. html_escape(pandoc.utils.stringify(title)) ..
        ')<strong>.</strong> ' ..
        html_escape(pandoc.utils.stringify(caption)) .. '</p>'
    return pandoc.RawBlock("html", html)
end

local function toc_label(number, title)
    local content = {}
    if number then
        append(content, pandoc.Str(number))
        append(content, pandoc.Space())
    end
    extend(content, title)
    return content
end

local function add_toc(state, level, label, target)
    local entry = {label = label, target = target, children = {}}

    if level == 0 then
        append(state.toc, entry)
        state.toc_part = entry
        state.toc_section = nil
    elseif level == 1 and state.toc_part then
        append(state.toc_part.children, entry)
        state.toc_section = entry
    elseif level == 2 and (state.toc_section or state.toc_part) then
        append((state.toc_section or state.toc_part).children, entry)
    else
        append(state.toc, entry)
        state.toc_part = entry
        state.toc_section = nil
    end
end

local function toc_items(entries)
    local items = {}
    for _, entry in ipairs(entries) do
        local blocks = {
            pandoc.Plain({pandoc.Link(entry.label, "#" .. entry.target)})
        }
        if #entry.children > 0 then
            append(blocks, pandoc.BulletList(toc_items(entry.children)))
        end
        append(items, blocks)
    end
    return items
end

local function toc_blocks(state)
    local blocks = {
        anchor("table-of-contents"),
        pandoc.Header(2, {
            pandoc.Strong({
                pandoc.Str("Table"),
                pandoc.Space(),
                pandoc.Str("of"),
                pandoc.Space(),
                pandoc.Str("Contents")
            })
        })
    }
    if #state.toc > 0 then
        append(blocks, pandoc.BulletList(toc_items(state.toc)))
    end
    return blocks
end

local function emit_proofs(output, state, proofs)
    if #proofs == 0 then
        return
    end

    add_toc(state, 0, {pandoc.Str("Proofs")}, "proofs")
    append(output, anchor("proofs"))
    append(output, pandoc.Header(2,
        {pandoc.Strong({pandoc.Str("Proofs")})}))

    for _, proof in ipairs(proofs) do
        append(output, anchor(proof.proof_id))
        local heading = {
            pandoc.Str("Proof"),
            pandoc.Space(),
            pandoc.Str("of"),
            pandoc.Space(),
            pandoc.Link(proof.title, "#" .. proof.theorem_id)
        }
        append(output, pandoc.Header(3, heading))
        extend(output, proof.blocks)
    end
end

local function emit_references(output, state)
    add_toc(state, 0, {pandoc.Str("References")}, "references")
    append(output, anchor("references"))
    append(output, pandoc.Header(2,
        {pandoc.Strong({pandoc.Str("References")})}))
end

function Pandoc(document)
    local output = {}
    local proofs = {}
    local proofs_emitted = false
    local state = {
        chapter = 0,
        section = 0,
        object = 0,
        part_num = nil,
        part_toc = nil,
        subpart_num = nil,
        subpart_toc = nil,
        toc = {},
        toc_part = nil,
        toc_section = nil
    }
    local index = 1

    while index <= #document.blocks do
        local block = document.blocks[index]
        local part_fields, part_title = structured_marker(
            block, "LaTeXToPart", 2)
        local subpart_fields, subpart_title = structured_marker(
            block, "LaTeXToSubPart", 2)
        local theorem_fields, theorem_title = structured_marker(
            block, "LaTeXToTheorem", 2)
        local definition_fields, definition_title = structured_marker(
            block, "LaTeXToDefinition", 2)
        local figure_fields, figure_title = structured_marker(
            block, "LaTeXToFigure", 2)
        local proof_link = marker_content(block, "LaTeXToProofLink")
        local proof_inline = marker_content(block, "LaTeXToProofInline")
        local proof_title = marker_content(block, "LaTeXToProofStart")

        if marker_content(block, "LaTeXToTOC") then
            append(output, pandoc.RawBlock("latex-to-placeholder", "toc"))
        elseif part_fields then
            state.part_num = root_mode(
                part_fields[1], "num", "nonum", "genPart")
            state.part_toc = root_mode(
                part_fields[2], "toc", "notoc", "genPart")
            state.section = 0
            state.object = 0
            state.toc_section = nil
            local number = nil
            if state.part_num == "num" then
                state.chapter = state.chapter + 1
                number = tostring(state.chapter)
            end
            local identifier = "chapter-" .. slug(part_title)
            append(output, anchor(identifier))
            append(output, titled_header(2, "Chapter", number, part_title))
            if state.part_toc == "toc" then
                add_toc(state, 0, toc_label(number, part_title), identifier)
            else
                state.toc_part = nil
            end
        elseif subpart_fields then
            state.subpart_num = resolved_mode(subpart_fields[1],
                state.part_num, "num", "nonum", "genSubPart")
            state.subpart_toc = resolved_mode(subpart_fields[2],
                state.part_toc, "toc", "notoc", "genSubPart")
            local number = nil
            if state.subpart_num == "num" then
                state.section = state.section + 1
                state.object = 0
                number = state.chapter .. "." .. state.section
            end
            local identifier = "section-" .. slug(subpart_title)
            append(output, anchor(identifier))
            append(output, titled_header(2, "Section", number, subpart_title))
            if state.subpart_toc == "toc" then
                add_toc(state, 1, toc_label(number, subpart_title), identifier)
            else
                state.toc_section = nil
            end
        elseif theorem_fields or definition_fields or figure_fields then
            local fields = theorem_fields or definition_fields or figure_fields
            local title = theorem_title or definition_title or figure_title
            local name = theorem_fields and "Theorem" or
                (definition_fields and "Definition" or "Figure")
            local prefix = name:lower()
            local num_mode = resolved_mode(fields[1], state.subpart_num,
                "num", "nonum", "gen" .. name)
            local toc_mode = resolved_mode(fields[2], state.subpart_toc,
                "toc", "notoc", "gen" .. name)
            local number = nil
            if num_mode == "num" then
                state.object = state.object + 1
                number = state.chapter .. "." .. state.section .. "." ..
                    state.object
            end
            local identifier = prefix .. "-" .. slug(title)
            append(output, anchor(identifier))
            local object_content = object_inlines(name, number, title)
            local statement = document.blocks[index + 1]
            local statement_content = {}
            if statement and statement.t == "Para" then
                statement_content = statement.content
                append(object_content, pandoc.Space())
                extend(object_content, statement.content)
                index = index + 1
            end
            if name == "Figure" then
                append(output,
                    centered_figure(number, title, statement_content))
            else
                append(output, pandoc.Para(object_content))
            end
            if toc_mode == "toc" then
                add_toc(state, 2, toc_label(number, title), identifier)
            end
        elseif proof_inline then
        elseif proof_link then
            local proof_id = "proof-of-" .. slug(proof_link)
            local link_content = {
                pandoc.Str("Proof"),
                pandoc.Space(),
                pandoc.Str("of"),
                pandoc.Space()
            }
            extend(link_content, proof_link)
            block.content = {
                pandoc.Strong({pandoc.Str("Proof")}),
                pandoc.Str("."),
                pandoc.Space(),
                pandoc.Str("See"),
                pandoc.Space(),
                pandoc.Link(link_content, "#" .. proof_id),
                pandoc.Str(".")
            }
            append(output, block)
        elseif proof_title then
            local proof_blocks = {}
            index = index + 1
            while index <= #document.blocks and not marker_content(
                document.blocks[index], "LaTeXToProofEnd") do
                append(proof_blocks, document.blocks[index])
                index = index + 1
            end
            if index > #document.blocks then
                error("theorem proof is missing its end marker", 0)
            end
            append(proofs, {
                title = proof_title,
                blocks = proof_blocks,
                theorem_id = "theorem-" .. slug(proof_title),
                proof_id = "proof-of-" .. slug(proof_title)
            })
        elseif marker_content(block, "LaTeXToReferences") then
            emit_proofs(output, state, proofs)
            proofs_emitted = true
            emit_references(output, state)
        else
            append(output, block)
        end

        index = index + 1
    end

    if not proofs_emitted then
        emit_proofs(output, state, proofs)
    end

    local final_output = {}
    local generated_toc = toc_blocks(state)
    for _, block in ipairs(output) do
        if block.t == "RawBlock" and
            block.format == "latex-to-placeholder" then
            extend(final_output, generated_toc)
        else
            append(final_output, block)
        end
    end

    return pandoc.Pandoc(final_output, document.meta)
end
