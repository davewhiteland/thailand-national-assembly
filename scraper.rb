#!/bin/env ruby
# encoding: utf-8

require 'scraperwiki'
require 'nokogiri'
# require 'open-uri/cached'
# OpenURI::Cache.cache_path = '.cache'
require 'open-uri'

# thai_senate URL gives photos and senate numerical IDs
# note "{PAGE-NUMBER}" placemarker will be replaced on the fly
thai_senate_url = "http://www.senate.go.th/w3c/senate/senator.php?id=18&page={PAGE-NUMBER}&orby=&orrg=ASC"

# Wikipedia has kindly separated out the honorifics
wikipedia_url = URI.encode('https://th.wikipedia.org/wiki/สภานิติบัญญัติแห่งชาติ_(ประเทศไทย)_พ.ศ._2557')

# Party: currently (2015) the assembly is appointed by the military junta, NCPO
# The senate website has a term_id but it doesn't seem to map to anything
# (because changing it doesn't make any difference); but as this assembly
# was appointed when the coup happened in 2557 BE (Thai calendar), that
# seems like a value to use?

$thai_party = 'NCPO'
$thai_term = '2557'

class String
  def tidy
    self.gsub(/[[:space:]]+/, ' ').strip
  end
end

def noko_for(url)
  Nokogiri::HTML(open(url).read)
end

def get_senate_url(url, page_number)
  return url.sub('{PAGE-NUMBER}', "#{page_number}")
end

# Thai honorifics are found by scraping wikipedia's entry for the senate.
# Can't do this on the official page because there's not always a space, etc.
# Note: return this list in descending honorific length (i.e., longest first).
# This is important because some honorifics may be compounded.
def scrape_wiki_list_for_honorifics(url)
  noko = noko_for(url)
  honorifics = []
  thai_id=".E0.B8.81.E0.B8.B2.E0.B8.A3.E0.B9.81.E0.B8.95.E0.B9.88.E0.B8.87.E0.B8.95.E0.B8.B1.E0.B9.89.E0.B8.87.E0.B8.A3.E0.B8.AD.E0.B8.9A.E0.B9.81.E0.B8.A3.E0.B8.81"
  noko.xpath(%Q{//h3[span[@id="#{thai_id}"]]/following-sibling::table[1]//ol/li[a]}).each do |li|
    honorifics << li.xpath('./text()[not(preceding-sibling::a)]').text().tidy
    # we're ignoring name because we get them from the Senate's own site,
    # but in case you want it: name = li.css('a[1]')a.text  :-)
  end
  return honorifics.uniq.sort_by{|x| x.length}.reverse
end

def split_honorific_and_name(raw_name, honorifics)
  honorific = nil
  name = raw_name
  honorifics.each do |hon|
    if name.sub!(hon, '')
      honorific = hon
      break
    end
  end
  return [name.tidy, honorific]
end

def scrape_senate_page(url, page_number, honorifics)
  url = get_senate_url(url, page_number)
  puts "--> scrape_senate_page(#{url})"
  noko = noko_for(url)
  qty_members = 0
  noko.xpath('//div[@id="maincontent"]//table[1]/tr[td]').each do |tr|
    tds = tr.css('td')
    senate_id = tds[0].text.tidy
    if senate_id.match(/^\d+$/)
      raw_name = tds[2].text.tidy
      name, honorific = split_honorific_and_name(raw_name, honorifics)
      data = { 
        id: senate_id,
        name: name,
        image: tds[1].xpath('./img/@src').text.tidy,
        title: honorific,
        party: $thai_party,
        term: $thai_term
      }
      ScraperWiki.save_sqlite([:id], data)
      qty_members+=1
    end
  end
  puts "    members on this page: #{qty_members}"
end

def get_number_of_senate_pages(url)
  url = get_senate_url(url, 1) # page number 1
  puts "--> scrape_senate_page(#{url})"
  noko = noko_for(url)
  page_menu = noko.xpath("//*[text()[contains(.,'หน้า')]]")
  return page_menu.xpath('./a[last()]').text().to_i
end

number_of_senate_pages = get_number_of_senate_pages(thai_senate_url)

honorifics = scrape_wiki_list_for_honorifics(wikipedia_url)
(1..number_of_senate_pages).each do |page_number|
  scrape_senate_page(thai_senate_url, page_number, honorifics)
end
