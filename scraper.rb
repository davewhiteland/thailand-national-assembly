#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pry'
require 'scraped'
require 'scraperwiki'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'
# require 'scraped_page_archive/open-uri'

# thai_senate URL gives photos and senate numerical IDs
# note "{PAGE-NUMBER}" placemarker will be replaced on the fly
thai_senate_url = 'https://www.senate.go.th/w3c/senate/senator.php?id=18&page={PAGE-NUMBER}&orby=&orrg=ASC'

# Party: currently (2015) the assembly is appointed by the military junta, NCPO
# The senate website has a term_id but it doesn't seem to map to anything
# (because changing it doesn't make any difference); but as this assembly
# was appointed when the coup happened in 2557 BE (Thai calendar), that
# seems like a value to use?

def noko_for(url)
  Nokogiri::HTML(open(url).read)
end

def senate_url(url, page_number)
  url.sub('{PAGE-NUMBER}', page_number.to_s)
end

# Thai honorifics are found by scraping wikipedia's entry for the senate.
# Can't do this on the official page because there's not always a space, etc.
# Note: return this list in descending honorific length (i.e., longest first).
# This is important because some honorifics may be compounded.
# TODO: move this to another scraper

# Wikipedia has kindly separated out the honorifics
WIKIPEDIA_URL = URI.encode('https://th.wikipedia.org/wiki/สภานิติบัญญัติแห่งชาติ_(ประเทศไทย)_พ.ศ._2557')

def wikipedia_honorifics
  noko = noko_for(WIKIPEDIA_URL)

  list_section_header = 'การแต่งตั้งรอบแรก'
  next_section_header = 'ข่าวเพิ่มเติม'

  list_header = noko.xpath('.//span[.="%s"]' % list_section_header)
  raise "Can't find #{list_section_header}" if list_header.empty?
  list_header.xpath('.//preceding::*').remove

  next_header = noko.xpath('.//span[.="%s"]' % next_section_header)
  raise "Can't find #{next_section_header}" if next_header.empty?
  next_header.xpath('.//following::*').remove

  # Whilst we're here also fetch and store all the linked Wikinames
  wikinames = noko.xpath('.//ol//li//a[not(@class="new")]/@title').map(&:text).map { |n| {name: n} }
  ScraperWiki.save_sqlite([:name], wikinames, 'wikinames')

  noko.xpath('.//ol//li[a]').map { |n| n.children.first }.map(&:text).map(&:tidy).uniq
end

def split_honorific_and_name(raw_name, honorifics)
  honorific = nil
  name = raw_name.tidy.strip
  honorifics.each do |hon|
    if name.sub!(/^#{hon}/, '')
      honorific = hon
      break
    end
  end
  [name.tidy, honorific]
end

def scrape_senate_page(url, page_number)
  honorifics = wikipedia_honorifics.sort_by(&:length).reverse
  url = senate_url(url, page_number)
  noko = noko_for(url)

  noko.xpath('//div[@id="maincontent"]//table[1]/tr[td]').each do |tr|
    tds = tr.css('td')
    senate_id = tds[0].text.tidy
    next unless senate_id =~ /^\d+$/

    raw_name = tds[2].text.tidy
    name, honorific = split_honorific_and_name(raw_name, honorifics)
    image_url = tds[1].xpath('./img/@src').text.tidy

    data = {
      id:               image_url[/([\d_]+).JPG/, 1].sub(/^_/, ''),
      name:             name,
      image:            image_url,
      honorific_prefix: honorific,
      party:            'NCPO',
      term:             '2557',
      source:           url,
    }
    puts data.reject { |_, v| v.to_s.empty? }.sort_by { |k, _| k }.to_h if ENV['MORPH_DEBUG']
    ScraperWiki.save_sqlite([:id], data)
  end
end

def number_of_senate_pages(url)
  url = senate_url(url, 1)
  noko_for(url).xpath("//*[text()[contains(.,'หน้า')]]/a[last()]").text.to_i
end

ScraperWiki.sqliteexecute('DROP TABLE data') rescue nil

(1..number_of_senate_pages(thai_senate_url)).each do |page_number|
  scrape_senate_page(thai_senate_url, page_number)
end
