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
(?:\s(?<species>(?:x\s)?[a-z-]{2,}(?:\s(?:subsp\.|var\.|f\.)\s[a-z-]{2,})*))?
(?:\s'(?<cultivar>.+)')?
\z/x

OBJECT_TYPES = 'node,way,closedway,multipolygon'

Taxon = Data.define(:genus, :species, :cultivar, :vernacular, :leaf_type)
class Taxon
  def full_taxon = [genus, species, cultivar && "‘#{cultivar}’"].compact.join(' ')
  def full_species
    return nil unless species
    [genus, species].join(' ')
  end
end

def parse_taxon(taxon)
  raise "Unexpected: #{taxon}" unless taxon =~ RE_TAXON
  $~.named_captures(symbolize_names: true).tap do |h|
    h[:species]&.gsub!('x ', "\u00D7 ")
  end
end

def generate_presets(csv, xml)
  taxa = csv.map do |taxon, vernacular, leaf_type|
    Taxon.new(**parse_taxon(taxon), vernacular:, leaf_type:)
  end
  species, genera = taxa.partition { it.species || it.cultivar }
  species = species.group_by { it.genus }

  genera.each do |genus|
    xml.add_element('chunk', 'id' => "genus-#{genus.genus}").tap do |chunk|
      chunk.add_element('key', 'key' => 'genus', 'value' => genus.genus)
      chunk.add_element('key', 'key' => 'genus:ja', 'value' => genus.vernacular)
    end

    xml.add_element('group', 'name' => genus.vernacular).tap do |group|
      group.add_element('item', 'name' => '*' + genus.vernacular, 'type' => OBJECT_TYPES, 'preset_name_label' => 'true').tap do |item|
        item.add_element('reference', 'ref' => "genus-#{genus.genus}")
        item.add_element('key', 'key' => 'taxon', 'value' => genus.genus)
        item.add_element('key', 'key' => "taxon:#{LANG}", 'value' => genus.vernacular)
        item.add_element('text', 'key' => 'taxon:cultivar', 'text' => 'Cultivar')
        item.add_element('text', 'key' => "taxon:cultivar:#{LANG}", 'text' => "Cultivar (#{LANG})", 'match' => 'none')
        item.add_element('key', 'key' => 'leaf_type', 'value' => genus.leaf_type, 'match' => 'none')
      end

      species[genus.genus]&.each do |species|
        name = species.cultivar ? "‘#{species.vernacular}’" : species.vernacular
        group.add_element('item', 'name' => name, 'type' => OBJECT_TYPES, 'preset_name_label' => 'true').tap do |item|
          item.add_element('reference', 'ref' => "genus-#{species.genus}")
          item.add_element('key', 'key' => 'species', 'value' => species.full_species)
          item.add_element('key', 'key' => 'taxon', 'value' => species.full_taxon)
          item.add_element('key', 'key' => "taxon:#{LANG}", 'value' => species.vernacular.sub('/\s*\(.+\)\z/', ''), 'match' => 'none')
          if species.cultivar
            item.add_element('key', 'key' => 'taxon:cultivar', 'value' => species.cultivar&.gsub(/\A'|'\z/, ''))
            item.add_element('key', 'key' => "taxon:cultivar:#{LANG}", 'value' => (species.vernacular.sub('/\s*\(.+\)\z/', '') if species.cultivar), 'match' => 'none')
          else
            item.add_element('text', 'key' => 'taxon:cultivar', 'text' => 'Cultivar')
            item.add_element('text', 'key' => "taxon:cultivar:#{LANG}", 'text' => "Cultivar (#{LANG})")
          end
          item.add_element('key', 'key' => 'leaf_type', 'value' => species.leaf_type, 'match' => 'none')
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
