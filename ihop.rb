#!/usr/bin/env ruby
require 'rest-client'
require 'json'
require 'irb'
require 'taglib'
require 'awesome_print'

DB_NAME = '.db.json'

module Downloadable
  def download
    `wget #@download_url -O '#{filename}'`
  end
end

module Tagable
  def tag
    TagLib::MPEG::File.open(filename) do |file|
      tag = file.id3v2_tag

      tag.album = album
      tag.artist = artist
      tag.title = title

      file.save
    end
  end
end

class Content
  include Downloadable
  include Tagable

  def initialize(params, session)
    @session = session
    @download_url = params.fetch('downloadUrl')
    @format = params.fetch('format')
    @filesize = params.fetch('fileSize')
  end

  def extension
    @format.downcase
  end

  def audio?
    false
  end

  def album
    @session.album
  end

  def artist
    @session.worship_leader
  end

  def title
    @session.title
  end

  def filename
    s = @session
    "#{s.started_at} - #{s.worship_leader}.#{extension}"
  end

  def pull
    download
    tag
  end
end

class AudioContent < Content
  def initialize(params, session)
    super
    @bitrate = params.fetch('bitrate')
  end

  def audio?
    true
  end
end

class OtherContent < Content
  def initialize(params, session)
    super
    @params = params
  end
end

class ContentBuilder
  def self.build(params, session)
    content_type = params.fetch('contentType')
    case content_type
    when 'audio'
      AudioContent.new(params, session)
    else
      OtherContent.new(params, session)
    end
  end
end

class Session
  attr_reader :started_at, :type, :worship_leader, :content

  def initialize(params)
    @started_at = params.fetch('title')
    @type = params.fetch('ihopkc$setType', ['Unknown']).join('/')
    @worship_leader = params.fetch('ihopkc$worshipLeader', ['Unknown']).join('/')
    @content = params.fetch('content').map { |c| ContentBuilder.build(c, self) }
  end

  def has_audio?
    @content.any?(&:audio?)
  end

  def audio_content
    @content.select(&:audio?)
  end

  def pull_audio
    content = audio_content.sample.pull
  end

  def album
    'Prayer Room'
  end

  def title
    "#@started_at - #@type"
  end
end

def usage
  puts "Usage #{$0} build|random"
  exit
end

def build
  File.open(DB_NAME, 'w') do |f|
    res = RestClient.get('http://feed.theplatform.com/f/IfSiAC/5ct7EYhhJs9Z', params: { range: '1-1000000', count: true })
    f.write(res.body)
  end
end

def random
  File.open(DB_NAME) do |f|
    data = f.read
    blob = JSON::parse(data)
    sessions = blob.fetch('entries').map { |e| Session.new(e) }
    random_session = sessions.select(&:has_audio?).sample
    random_session.pull_audio
  end
end

if ARGV.length < 1
  usage
end

command = ARGV.fetch(0)

case command
when 'build'
  build
when 'random'
  random
else
  usage
end
