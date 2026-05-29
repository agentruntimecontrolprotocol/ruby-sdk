#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates Markdown API reference docs from YARD-style comments in lib/.
# Pure stdlib so it runs on Ruby 2.6+.
#
# Walks lib/**/*.rb. For each file, extracts:
#   - top-of-file comment block (module/file overview)
#   - each module/class/def declaration with the preceding comment block
#
# Emits one Markdown file per source file to docs/api/<relative_path>.md plus
# a docs/api/index.md listing every page.

require 'fileutils'
require 'pathname'

ROOT = Pathname.new(File.expand_path('..', __dir__))
LIB  = ROOT.join('lib')
OUT  = ROOT.join('docs', 'api')

# Strip a leading "# " or "#" from a comment line, preserving inner spaces.
def strip_comment(line)
  line.sub(/\A\s*#\s?/, '').rstrip
end

# Read the contiguous comment block ending at index `idx - 1` (lines array).
# Returns (start_index, [stripped_lines]). Empty array if no block.
def read_block_before(lines, idx)
  i = idx - 1
  collected = []
  while i >= 0 && lines[i] =~ /\A\s*#/
    collected.unshift(strip_comment(lines[i]))
    i -= 1
  end
  # Skip frozen_string_literal / encoding / shebang style magic comments at top
  collected.reject! { |l| l =~ /\A(frozen_string_literal|encoding|warn_indent):/ }
  [i + 1, collected]
end

# Top-of-file comment block: skip shebang/magic-comments, then take leading #.
def file_overview(lines)
  i = 0
  i += 1 if lines[i] =~ /\A#!/
  while lines[i] && lines[i] =~ /\A\s*#\s*(frozen_string_literal|encoding|warn_indent):/i
    i += 1
  end
  i += 1 while lines[i] && lines[i].strip.empty?
  block = []
  while lines[i] && lines[i] =~ /\A\s*#/
    block << strip_comment(lines[i])
    i += 1
  end
  block
end

DECL_RE = /\A(\s*)(module|class|def)\s+([^\s(;]+)(.*)\z/.freeze

# For `def` signatures that span multiple physical lines (trailing `,` or open
# paren without matching close), keep appending until balanced.
def join_continued_signature(lines, idx)
  sig = lines[idx].rstrip
  i = idx
  loop do
    opens  = sig.count('(') + sig.count('[')
    closes = sig.count(')') + sig.count(']')
    trailing_comma = sig =~ /,\s*\z/
    break unless trailing_comma || opens > closes
    i += 1
    break unless lines[i]
    sig = "#{sig}\n#{lines[i].rstrip}"
  end
  sig
end

# Build a stack of enclosing module/class names by tracking `module`/`class`/`end`.
def parse_declarations(lines)
  results = []
  stack = []
  lines.each_with_index do |raw, idx|
    line = raw.rstrip
    next if line.strip.empty?
    if (m = line.match(DECL_RE))
      kind = m[2]
      name = m[3]
      tail = m[4].to_s.rstrip
      _start, comment = read_block_before(lines, idx)
      full = kind == 'def' ? join_continued_signature(lines, idx).sub(/\A\s+/, '') : "#{kind} #{name}#{tail}"
      sig = full
      qualified = if kind == 'def'
                    sep = name.start_with?('self.') ? '.' : '#'
                    base = stack.join('::')
                    base.empty? ? sig : "#{base}#{sep}#{name.sub(/\Aself\./, '')}"
                  else
                    (stack + [name]).join('::')
                  end
      results << { kind: kind, name: name, qualified: qualified, signature: sig.strip, comment: comment }
      stack.push(name) if kind == 'module' || kind == 'class'
    elsif line =~ /\A\s*end\b/ && !stack.empty?
      # crude: pop on bare `end`. Method `end`s also pop nothing since we don't push for def.
      # We only pop when the `end` is at the indentation of the top stack frame's owner;
      # to avoid building a full parser we just pop on any bare `end` that isn't inside
      # a `def` block. Since we don't track def open/close, this overpops; mitigate by
      # only popping when the line is exactly "end" (no trailing modifier) and dedented
      # to column 0..N matching stack depth heuristically.
      indent = line[/\A\s*/].length
      expected = (stack.length - 1) * 2
      stack.pop if indent <= expected
    end
  end
  results
end

def render_comment(lines)
  return '' if lines.empty?
  # Split into prose body vs YARD tag groups. A tag group starts at @tag and
  # absorbs subsequent indented continuation lines.
  body = []
  tags = []
  current = nil
  lines.each do |l|
    if l =~ /\A@\w/
      tags << (current = [l])
    elsif current && (l.start_with?('  ') || l.strip.empty?)
      current << l
    else
      current = nil
      body << l
    end
  end
  out = body.join("\n").strip
  unless tags.empty?
    out += "\n\n" unless out.empty?
    out += tags.map do |grp|
      head = grp[0]
      rest = grp[1..].to_a.reject { |x| x.strip.empty? }
      if rest.empty?
        "- `#{head}`"
      else
        code = rest.map { |x| x.sub(/\A  /, '') }.join("\n")
        "**`#{head}`**\n\n```ruby\n#{code}\n```"
      end
    end.join("\n\n")
  end
  out
end

def render_file(rel_path, lines)
  overview = file_overview(lines)
  decls = parse_declarations(lines)
  io = +""
  io << "# `#{rel_path}`\n\n"
  unless overview.empty?
    io << render_comment(overview) << "\n\n"
  end
  if decls.empty?
    io << "_No documented declarations._\n"
    return io
  end
  decls.each do |d|
    heading = d[:kind] == 'def' ? d[:qualified] : "#{d[:kind].capitalize} `#{d[:qualified]}`"
    io << "## #{heading}\n\n"
    io << "```ruby\n#{d[:signature]}\n```\n\n"
    body = render_comment(d[:comment])
    io << (body.empty? ? "_(undocumented)_\n\n" : body + "\n\n")
  end
  io
end

FileUtils.rm_rf(OUT)
FileUtils.mkdir_p(OUT)

files = Dir.glob(LIB.join('**', '*.rb')).sort
pages = []

files.each do |path|
  rel = Pathname.new(path).relative_path_from(ROOT).to_s
  lines = File.readlines(path, chomp: true)
  md = render_file(rel, lines)
  out_rel = Pathname.new(path).relative_path_from(LIB).sub_ext('.md').to_s
  out_path = OUT.join(out_rel)
  FileUtils.mkdir_p(out_path.dirname)
  File.write(out_path, md)
  pages << out_rel
end

index = +"# API Reference\n\nGenerated from `lib/` sources. One page per source file.\n\n"
pages.sort.each do |p|
  title = p.sub(/\.md\z/, '')
  index << "- [`#{title}`](./#{p})\n"
end
File.write(OUT.join('index.md'), index)

puts "Generated #{pages.length} pages + index.md at #{OUT.relative_path_from(ROOT)}/"
