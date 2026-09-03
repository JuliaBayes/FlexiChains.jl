# Avoid printing the entire `Sampled` object if it's been constructed
_show_range(s::DD.Dimensions.Lookups.Lookup) = _show_range(parent(s))
_show_range(s::AbstractRange) = string(s)
function _show_range(s::AbstractVector)
    if length(s) > 5
        return "[$(first(s)) … $(last(s))]"
    else
        return string(s)
    end
end
function _show_range(s::AbstractVector{<:Symbol})
    return "[" * join(string.(s), ", ") * "]"
end

# ── Box-drawing display ──────────────────────────────────────────

const _BOX_COLOR = :light_black
const _ELTYPE_COLOR = :green
const _MAX_BOX_WIDTH = 120

struct _Segment
    text::String
    bold::Bool
    color::Symbol
end
_Segment(text::String; bold::Bool=false, color::Symbol=:normal) =
    _Segment(text, bold, color)

function _print_segment(io::IO, s::_Segment)
    printstyled(io, s.text; bold=s.bold, color=s.color)
    return textwidth(s.text)
end

function _box_width(io::IO)
    return min(displaysize(io)[2], _MAX_BOX_WIDTH)
end

function _box_header(io::IO, width::Int, title::AbstractString)
    printstyled(io, '╭', "─"; color=_BOX_COLOR)
    printstyled(io, title; bold=true)
    used = 2 + textwidth(title)
    fill = max(width - used - 1, 0)
    if fill > 1
        printstyled(io, " ", "─"^(fill - 1); color=_BOX_COLOR)
    elseif fill == 1
        printstyled(io, " "; color=_BOX_COLOR)
    end
    return printstyled(io, '╮'; color=_BOX_COLOR)
end

function _box_content(f::Function, io::IO, width::Int)
    printstyled(io, "│"; color=_BOX_COLOR)
    print(io, " ")
    visible = f(io)::Int
    pad = max(width - visible - 4, 0)
    print(io, " "^(pad + 1))
    return printstyled(io, "│"; color=_BOX_COLOR)
end

function _box_content(io::IO, width::Int, segments::Vector{_Segment})
    return _box_content(io, width) do io
        visible = 0
        for seg in segments
            visible += _print_segment(io, seg)
        end
        return visible
    end
end

function _box_empty(io::IO, width::Int)
    printstyled(io, "│"; color=_BOX_COLOR)
    print(io, " "^max(width - 2, 0))
    return printstyled(io, "│"; color=_BOX_COLOR)
end

function _box_bottom(io::IO, width::Int)
    return printstyled(io, "╰", "─"^max(width - 2, 0), "╯"; color=_BOX_COLOR)
end

# ── Text helpers ─────────────────────────────────────────────────

function _truncate_textwidth(s::AbstractString, maxw::Int)
    w = 0
    for (i, c) in enumerate(s)
        w += textwidth(c)
        if w >= maxw
            return s[1:prevind(s, i)] * "…"
        end
    end
    return s
end

struct NameWithSize{T<:Union{Nothing,Tuple}}
    name::String
    size::T # nothing to indicate mixed size / non-array
end
_name_text(nws::NameWithSize{Nothing}) = nws.name
_name_text(nws::NameWithSize{<:Tuple}) = "$(nws.name) $(nws.size)"
Base.textwidth(nws::NameWithSize) = textwidth(_name_text(nws))

function _wrap_items(
    items::Vector{NameWithSize},
    available::Int,
)::Vector{Vector{NameWithSize}}
    isempty(items) && return Vector{NameWithSize}[]

    # Calculate the total width of all items, including commas and spaces
    full_tw = sum(textwidth, items) + 2 * (length(items) - 1)
    # If it fits on one line, we can return as a single line
    full_tw <= available && return [items]

    lines = Vector{NameWithSize}[]

    # Try to fit as many items as possible plus the trailing comma onto the current line
    # (a greedy algorithm). This could in principle be more fancy (e.g. Knuth-Plass)...
    current_line = NameWithSize[]
    remaining = available
    for item in items
        tw = textwidth(item)
        if tw + 1 > remaining && !isempty(current_line)
            # Can't fit the next one on this line, so push the current line and start a new
            # one. But if the current line is empty, we have to put it on this line anyway.
            push!(lines, current_line)
            current_line = NameWithSize[]
            remaining = available
        end
        push!(current_line, item)
        remaining -= (tw + 2)
    end
    push!(lines, current_line)
    return lines
end

# Choose which lines to print - for horizontal printing of long vectors of parameters
function _elided_line_indices(n::Int; max_lines = 4)
    n <= max_lines && return Union{Int,Nothing}[1:n;]
    n_head = max_lines ÷ 2
    n_tail = div(max_lines - 1, 2)
    return Union{Int,Nothing}[1:n_head; nothing; (n - n_tail + 1):n]
end

_maybe_s(x) = x == 1 ? "" : "s"

# ── Composable display blocks ───────────────────────────────────

function _print_dims(io::IO, chain::FlexiChain, width::Int)
    iter_range = _show_range(FlexiChains.iter_indices(chain))
    chain_range = _show_range(FlexiChains.chain_indices(chain))
    label_width = max(textwidth("iter"), textwidth("chain"))
    for (clr, sym, label, range) in (
        (DD.dimcolor(1), DD.dimsymbol(1), "iter", iter_range),
        (DD.dimcolor(2), DD.dimsymbol(2), "chain", chain_range),
    )
        _box_content(io, width) do io
            s = "$sym $(rpad(label, label_width)) = $range"
            printstyled(io, s; color=clr)
            return textwidth(s)
        end
        println(io)
    end
    return
end

function _eltype_groups(cs::ChainOrSummary, is_parameters::Bool)
    groups = OrderedDict{String,Vector{NameWithSize}}()
    for key in keys(cs)
        if is_parameters && key isa Extra
            continue
        elseif !is_parameters && key isa Parameter
            continue
        end

        data = cs._data[key]
        T = eltype(data)
        T_str = string(T)
        if !haskey(groups, T_str)
            groups[T_str] = NameWithSize[]
        end

        sz = if T <: AbstractArray && !isempty(data)
            # Check if data is all the same size
            sz = size(first(data))
            if all(x -> size(x) == sz, data)
                sz
            else
                nothing
            end
        else
            nothing
        end
        push!(groups[T_str], NameWithSize(string(get_name(key)), sz))
    end
    return groups
end

function _print_eltype_groups(
    io::IO,
    groups::OrderedDict{String,Vector{NameWithSize}},
    width::Int,
)
    max_type_cap = max(div(width, 2), 12)
    raw_tw = maximum(textwidth, keys(groups))
    max_tw = min(raw_tw, max_type_cap)
    prefix_width = 1 + max_tw + 2
    names_width = max(width - 4 - prefix_width, 1)

    for (type_str, names) in groups
        display_type = if textwidth(type_str) > max_tw
            rpad(_truncate_textwidth(type_str, max_tw), max_tw)
        else
            rpad(type_str, max_tw)
        end
        wrapped = _wrap_items(names, names_width)
        nlines = length(wrapped)
        for li in _elided_line_indices(nlines)
            if isnothing(li)
                _box_content(io, width) do io
                    print(io, " "^prefix_width)
                    printstyled(io, "⋮"; color=_BOX_COLOR)
                    return prefix_width + 1
                end
                println(io)
                continue
            end
            nwss = wrapped[li]
            trailing = li < nlines ? "," : ""
            _box_content(io, width) do io
                if li == 1
                    print(io, " ")
                    printstyled(io, display_type; color=_ELTYPE_COLOR)
                    print(io, "  ")
                else
                    print(io, " "^prefix_width)
                end
                tw = prefix_width
                n_nws = length(nwss)
                for (i, nws) in enumerate(nwss)
                    print(io, _name_text(nws))
                    tw += textwidth(nws)
                    if i < n_nws
                        print(io, ", ")
                        tw += 2
                    else
                        print(io, trailing)
                        tw += textwidth(trailing)
                    end
                end
                return tw
            end
            println(io)
        end
    end
    return
end

function _print_section(
    io::IO,
    width::Int,
    title::String,
    eltype_groups::OrderedDict{String,Vector{NameWithSize}};
    subtitle::String="",
)
    _box_empty(io, width)
    println(io)
    segments = [_Segment(title; bold=true)]
    if !isempty(subtitle)
        push!(segments, _Segment(subtitle; color=:light_black))
    end
    _box_content(io, width, segments)
    println(io)
    return if isempty(eltype_groups)
        _box_content(io, width, [_Segment(" (none)"; color=:light_black)])
        println(io)
    else
        _print_eltype_groups(io, eltype_groups, width)
    end
end

# ── show(FlexiChain) ─────────────────────────────────────────────

function Base.show(io::IO, ::MIME"text/plain", chain::FlexiChain{TKey}) where {TKey}
    ni, nc = size(chain)
    width = _box_width(io)

    title = "FlexiChain ($ni iteration$(_maybe_s(ni)), $nc chain$(_maybe_s(nc)))"
    _box_header(io, width, title)
    println(io)

    _print_dims(io, chain, width)

    _print_section(
        io,
        width,
        "Parameters ($(length(parameters(chain))))",
        _eltype_groups(chain, true);
        subtitle=" ── $TKey",
    )

    _print_section(
        io,
        width,
        "Extras ($(length(extras(chain))))",
        _eltype_groups(chain, false),
    )

    _box_bottom(io, width)
    return nothing
end

# ── show(FlexiSummary) ──────────────────────────────────────

function _print_summary_dims(io::IO, summary::FlexiSummary, width::Int)
    ii = iter_indices(summary)
    ci = chain_indices(summary)
    si = stat_indices(summary)

    all_dims = Tuple{String,Union{String,Nothing}}[
        ("iter", isnothing(ii) ? nothing : _show_range(ii)),
        ("chain", isnothing(ci) ? nothing : _show_range(ci)),
        ("stat", isnothing(si) ? nothing : _show_range(si)),
    ]

    label_width = maximum(textwidth(d[1]) for d in all_dims)
    color_counter = 1
    for (label, range) in all_dims
        _box_content(io, width) do io
            if isnothing(range)
                s = "  $(rpad(label, label_width))   collapsed"
                printstyled(io, s; color=:white)
            else
                sym = DD.dimsymbol(color_counter)
                clr = DD.dimcolor(color_counter)
                prefix = "$sym $(rpad(label, label_width)) = "
                max_range = width - 4 - textwidth(prefix)
                range_str = if textwidth(range) > max_range
                    _truncate_textwidth(range, max_range)
                else
                    range
                end
                s = prefix * range_str
                printstyled(io, s; color=clr)
            end
            return textwidth(s)
        end
        println(io)
        if !isnothing(range)
            color_counter += 1
        end
    end
    return
end

function _print_summary_table(
    io::IO,
    summary::FlexiSummary,
    param_names::Vector,
    column_indices,
    first_column_prefix::String,
    width::Int,
)
    _box_empty(io, width)
    println(io)
    _box_content(io, width, [_Segment("Summary"; bold=true)])
    println(io)

    MAX_COL_WIDTH = 12
    inner_width = width - 4
    colpadding = 2

    # Limit the number of rows and columns printed
    screen_rows = displaysize(io)[1]
    max_formatted_rows = max(4 * screen_rows, 100)
    max_formatted_columns = max(div(inner_width, colpadding + 1), 1)

    shown_param_names = if length(param_names) <= max_formatted_rows
        param_names
    else
        half = max_formatted_rows ÷ 2
        vcat(first(param_names, half), last(param_names, max_formatted_rows - half))
    end
    header_col = [
        "param",
        map(p -> _truncate(_pretty_value(p), MAX_COL_WIDTH), shown_param_names)...,
    ]
    param_values = map(pn -> summary[pn], shown_param_names)

    value_cols = if isnothing(column_indices)
        [["", [_truncate(_pretty_value(value), MAX_COL_WIDTH) for value in param_values]...],]
    else
        column_names = Iterators.take(parent(column_indices), max_formatted_columns)
        map(enumerate(column_names)) do (column_i, column_name)
            column_header = _pretty_value(column_name)
            if column_i == 1
                column_header = first_column_prefix * column_header
            end
            [
                _truncate(column_header, MAX_COL_WIDTH)
                [
                    _truncate(_pretty_value(value[column_i]), MAX_COL_WIDTH) for
                    value in param_values
                ]...
            ]
        end
    end

    rows = hcat(header_col, value_cols...)

    buf = IOBuffer()
    ctx = IOContext(buf, :limit => true, :displaysize => (screen_rows, inner_width))
    Base.print_matrix(ctx, Text.(rows), " ", "  ", " ")
    for line in split(String(take!(buf)), '\n')
        _box_content(io, width) do io
            print(io, line)
            return textwidth(line)
        end
        println(io)
    end
    return
end

function Base.show(io::IO, ::MIME"text/plain", summary::FlexiSummary{TKey}) where {TKey}
    width = _box_width(io)

    ii = iter_indices(summary)
    ci = chain_indices(summary)
    si = stat_indices(summary)

    parts = String[]
    if !isnothing(ii)
        n = length(ii)
        push!(parts, "$n iteration$(_maybe_s(n))")
    end
    if !isnothing(ci)
        n = length(ci)
        push!(parts, "$n chain$(_maybe_s(n))")
    end
    if !isnothing(si)
        n = length(si)
        push!(parts, "$n statistic$(_maybe_s(n))")
    end

    title = if isempty(parts)
        "FlexiSummary"
    else
        "FlexiSummary ($(join(parts, ", ")))"
    end

    _box_header(io, width, title)
    println(io)

    _print_summary_dims(io, summary, width)

    param_names = parameters(summary)
    _print_section(
        io,
        width,
        "Parameters ($(length(param_names)))",
        _eltype_groups(summary, true);
        subtitle=" ── $TKey",
    )

    _print_section(
        io,
        width,
        "Extras ($(length(extras(summary))))",
        _eltype_groups(summary, false),
    )

    uncollapsed_indices = filter(!isnothing, (ii, ci, si))
    if length(uncollapsed_indices) <= 1 && !isempty(param_names)
        column_indices = isempty(uncollapsed_indices) ? nothing : only(uncollapsed_indices)
        first_column_prefix = if !isnothing(column_indices) && column_indices === ii
            "iter "
        elseif !isnothing(column_indices) && column_indices === ci
            "chain "
        else
            ""
        end
        _print_summary_table(
            io,
            summary,
            param_names,
            column_indices,
            first_column_prefix,
            width,
        )
    end

    _box_bottom(io, width)
    return nothing
end
