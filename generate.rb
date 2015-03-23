#!/usr/bin/env ruby

require 'nokogiri'
require 'open-uri'
require 'sqlite3'

PWD = Dir.pwd

#
# Create any of the default docset file structure that we may need
#
def resetDocsetDir
  if Dir.exist? './Splunk.docset'
    `rm -Rf ./Splunk.docset`
  end

  Dir.mkdir('./Splunk.docset')
  Dir.mkdir('./Splunk.docset/Contents')
  Dir.mkdir('./Splunk.docset/Contents/Resources')
  Dir.mkdir('./Splunk.docset/Contents/Resources/Documents')

  # get icon.png file

  `wget http://www.splunk.com/content/dam/splunk2/images/icons/favicons/favicon-32x32.png -O ./Splunk.docset/icon.png`

  # copy Info.plist file
  `cp ./template/Info.plist ./Splunk.docset/Contents`
end

#
# create the sqlite index
#
def createSQLiteDB
  if File.exist? './Splunk.docset/Contents/Resources/docSet.dsidx'
    File.delete './Splunk.docset/Contents/Resources/docSet.dsidx'
  end
  db = SQLite3::Database.new './Splunk.docset/Contents/Resources/docSet.dsidx'

  db.execute 'CREATE TABLE searchIndex(id INTEGER PRIMARY KEY, name TEXT, type TEXT, path TEXT);'
  db.execute 'CREATE UNIQUE INDEX anchor ON searchIndex (name, type, path);'
  return db
end

#
# Given an html file path, open it, parse it, clean it up,
# and overwirte the existing file.
#
def cleanupHtml(file)
  original = File.open(file)
  page = Nokogiri::HTML(original)
  original.close

  page.xpath('//comment()').each { |comment| comment.remove }

  page.css('#header').remove
  page.css('.bc_bg').remove
  page.css('.head_bg').remove

  page.css('.mainArticleHeader').remove
  page.css('.table_of_contents').remove

  sidebar = page.css('.wikiSidebarBox')[0]
  sidebar.parent.remove

  answers = page.css('#Answers')[0]
  if answers
    answersh2 = answers.parent
    if answersh2
      answersp = answersh2.next_element
      answersp.remove
    end
    answersh2.remove
  end

  page.css('.footer').remove
  page.css('#footerPagination').remove

  page.css('.affectedVersions').remove

  # write the new version
  articleFile = File.open(file,mode="w")
  articleFile.puts page.to_s
  articleFile.flush
  articleFile.close
  puts "saved cleaned up #{file}"
end

def main
  # delete the old dir and setup a new one
  resetDocsetDir
  
  db = createSQLiteDB
  
  Dir.chdir './Splunk.docset/Contents/Resources/Documents'

  # grab the list of search commands to be used as the default page for splunk docs
  listUrl = 'http://docs.splunk.com/Documentation/Splunk/latest/SearchReference/ListOfSearchCommands'
  listHtml = Nokogiri::HTML(open(listUrl))

  `wget -E -H -k -K -p -nc #{listUrl}`
  cleanupHtml("./docs.splunk.com/Documentation/Splunk/latest/SearchReference/ListOfSearchCommands.html")

  table = listHtml.css("table")[0]
  links = table.css("code a")
  
  # parse out all of the commands into urls for us to crawl
  commands = {}
  links.each do |l|
    commands[l.text] = l.attribute("href").value
  end  

  # for each command, wget it, then clean it up
  commands.each do |command, url|
    `wget -E -H -k -K -p #{url}`
    
    # cleanup the tail end of the URL using 
    base = './docs.splunk.com/Documentation/Splunk/6.2.2/SearchReference/'
    page = url.split('/').last
    path = base + page + '.html'
    cleanupHtml(path)
    
    # for each thing we want to link to, populate the sqlite index
    db.execute "INSERT OR IGNORE INTO searchIndex(name, type, path) VALUES ('#{command}', 'Command', '#{path}');"
  end

  Dir.chdir PWD

  # # do any general cleanup inside the docset file structure
  #
  # f = File.open("list.html")
  # doc = Nokogiri::HTML(f)
  #
  # links = doc.xpath('//a')
  # sections = {}
  #
  # links.each do |l|
  #   sections[l.text] = l.attribute('href').value
  # end
end

main
