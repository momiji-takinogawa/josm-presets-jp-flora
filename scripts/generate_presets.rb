#!/usr/bin/env ruby
require 'pathname'
require 'csv'
require 'rexml'

ROOT = Pathname(__dir__).parent
DIST = ROOT.join('dist').tap(&:mkpath)
FILES = { '樹木' => 'trees.csv' }
LANG = 'ja'

RE_TAXON = /\A
(?<genus>[A-Z][a-z-]+)
(?:\s(?<species>(?:x\s)?[a-z-]{2,}(?:\s(?:ssp\.|var\.|f\.)\s[a-z-]{2,})*))?
(?:\s(?<cultivar>'.+?'))?
\z/x

Taxon = Data.define(:genus, :species, :cultivar, :vernacular)

def parse_taxon(taxon)
  raise "Unexpected: #{taxon}" unless taxon =~ RE_TAXON
  $~.named_captures(symbolize_names: true)
end

def generate_presets(csv, xml)
  taxa = csv.map do |taxon, vernacular|
    Taxon.new(**parse_taxon(taxon), vernacular:)
  end
  species, genera = taxa.partition { it.species || it.cultivar }
  species = species.group_by { it.genus }

  genera.each do |genus|
    xml.add_element('chunk', 'id' => "genus-#{genus.genus}").tap do |chunk|
      chunk.add_element('key', 'key' => 'genus', 'value' => genus.genus)
      chunk.add_element('key', 'key' => 'genus:ja', 'value' => genus.vernacular)
    end

    xml.add_element('group', 'name' => genus.vernacular).tap do |group|
      group.add_element('item', 'name' => '*' + genus.vernacular, 'type' => 'node,closedway,multipolygon', 'preset_name_label' => 'true').tap do |item|
        item.add_element('reference', 'ref' => "genus-#{genus.genus}")
        item.add_element('text', 'key' => 'taxon', 'text' => 'Taxon', 'default' => genus.genus)
        item.add_element('text', 'key' => "taxon:#{LANG}", 'text' => "Taxon (#{LANG})", 'default' => genus.vernacular)
        item.add_element('text', 'key' => 'taxon:cultivar', 'text' => 'Cultivar')
        item.add_element('text', 'key' => "taxon:cultivar:#{LANG}", 'text' => "Cultivar (#{LANG})")
      end

      species[genus.genus]&.each do |species|
        cv = species.cultivar ? ' (栽培品種)' : ''
        group.add_element('item', 'name' => species.vernacular + cv, 'type' => 'node,closedway,multipolygon', 'preset_name_label' => 'true').tap do |item|
          item.add_element('reference', 'ref' => "genus-#{species.genus}")
          item.add_element('text', 'key' => 'taxon', 'text' => 'Taxon', 'default' => [species.genus, species.species, species.cultivar].compact.join(' '))
          item.add_element('text', 'key' => "taxon:#{LANG}", 'text' => 'Taxon (ja)', 'default' => species.vernacular)
          item.add_element('text', 'key' => 'taxon:cultivar', 'text' => 'Cultivar', 'default' => species.cultivar&.gsub(/\A'|'\z/, ''))
          item.add_element('text', 'key' => "taxon:cultivar:#{LANG}", 'text' => "Cultivar (#{LANG})", 'default' => (species.vernacular if species.cultivar))
        end
      end
    end
  end
end

xml = REXML::Document.new
xml << REXML::XMLDecl.new('1.0', 'UTF-8')
presets = xml.add_element('presets', 'xmlns' => 'http://josm.openstreetmap.de/tagging-preset-1.0', 'baselanguage' => LANG, 'version' => ENV['GITHUB_REF_NAME'])
FILES.each do |name, path|
  csv = CSV.read(ROOT + path)

  presets.add_element('group', 'name' => name).tap do |group|
    generate_presets(csv, group)
  end
end

File.open(DIST / 'presets.xml', 'w') do |f|
  xml.write(output: f, indent: 1, transitive: true)
end

Dir.chdir(DIST) do
  system 'zip', '-r', '../presets', '.'
end
