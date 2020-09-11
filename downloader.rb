#!/usr/bin/env ruby
# frozen_string_literal: true

require('nokogiri')
require('httparty')
require('pry')

CATALOG = URI.parse('https://charts.noaa.gov/RNCs/RNCProdCat_19115.xml')
PDF_PREFIX = 'https://charts.noaa.gov/PDFs'

SearchString = %w[
  identificationInfo
  MD_DataIdentification
  citation
  CI_Citation
].join(' ').freeze

def log(*args)
  args.each { |m| warn(m) }
end

def croak(*args)
  log(*args)
  exit(args.join.length % 255)
end

def download_catalog
  log('downloading chart catalog')

  res = Net::HTTP.get_response(CATALOG)

  if res.code.to_i >= 200 && res.code.to_i < 300
    res.body
  else
    croak("error #{res.code}", res.body)
  end
end

def create_chart_hash(catalog)
  catalog_data = Nokogiri::XML(catalog)

  charts = []

  catalog_data.css(SearchString).each do |chart|
    one_chart = {}

    one_chart[:chart_number] = chart.css('title gco|CharacterString').text
    one_chart[:title] = chart.css('alternateTitle gco|CharacterString').text

    charts << one_chart unless one_chart[:title].empty?
  end

  charts
end

def download_chart(chart_number:, title:)
  remote_name = "#{chart_number}.pdf"
  saved_name = "#{chart_number} - #{title}.pdf"
  destination = File.join('./charts', saved_name)

  file_uri = URI.parse(File.join(PDF_PREFIX, remote_name))

  head = HTTParty.head(file_uri)
  http_code = head.code.to_i
  http_length = head.content_length

  if http_code >= 300
    log("skipping #{saved_name} due to remote error : #{http_code}")
    return
  end

  if File.exist?(destination) && File.size(destination) == http_length
    log("skipping #{saved_name} since already present")
    return
  elsif File.exist?(destination)
    log("cleaning incomplete #{saved_name}")
    File.unlink(destination)
  end

  f = open(destination, 'w')

  begin
    log("downloading #{saved_name}")

    HTTParty.get(file_uri, stream_body: true) do |fragment|
      f.write(fragment)
    end
  ensure
    f.close
  end
end

charts = create_chart_hash(download_catalog)

log('starting dowloads')

charts.each do |chart|
  download_chart(**chart)
end
