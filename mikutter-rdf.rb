# -*- coding: utf-8 -*-
# Mikutter RDF
# つぶやきに含まれるURLをRDFに吐くプラグイン
# http://127.0.0.1:ポート番号/mikutter.xmlにアクセス！

require "yaml"
require "rss/1.0"
require "rss/maker"
require 'webrick'


class MikutterRDF
  def initialize()
    if UserConfig[:rdf_cache] == nil
      @cache = Array.new
      UserConfig[:rdf_cache] = YAML.dump(@cache)
    end

    @cache = YAML.load(UserConfig[:rdf_cache])
  end

  # URL付きのツイートをくいッとする
  def add_message_if_needed(message)
    if message[:message] =~ /(http[s]?\:\/\/[\w\+\$\;\?\.\%\,\!\#\~\*\/\:\@\&\\\=\_\-]+)/
      if !@cache.find { |i| i[:id] == message[:id] }
        item = {}

        item[:title] = "[" + message[:user][:name] + "]" + message[:message]
        item[:url] = $1
        item[:date] = message[:created]
        item[:id] = message[:id]

        @cache << item

        if @cache.size > 20
          @cache = @cache[@cache.size - 20..-1]
        end
      end

      UserConfig[:rdf_cache] = YAML.dump(@cache)
    end
  end

  # RDFを取得する
  def get_rdf(title)
    rss = RSS::Maker.make("1.0") do |maker|
      maker.channel.about = "http://mikutter.hachune.net/"
      maker.channel.title = title
      maker.channel.date = Time.now.iso8601
      maker.channel.description = "みくったーで話題のサイトです"
      maker.channel.link = "http://mikutter.hachune.net/"

      maker.items.do_sort = true

      @cache.each do |item|
        rdf_item = maker.items.new_item
        rdf_item.link = item[:url]
        rdf_item.title = item[:title]
        rdf_item.date = item[:date]
      end
    end

    rss.to_s
  end
end


Plugin.create(:rdf) do

  if UserConfig[:rdf_port] == nil
    UserConfig[:rdf_port] == 10251
  end

  if UserConfig[:rdf_title] == nil
    UserConfig[:rdf_title] == "mikutter"
  end


  # 設定画面
  settings "RDF" do
    adjustment("ポート番号（要再起動）", :rdf_port, 10251, 65535)
    input("タイトル", :rdf_title)
  end  


  rdf_rdf = MikutterRDF.new

  # 起動時処理
  onboot do |service|
    begin
      # Webサーバスレッドを起動
      thread = Thread.new do
        begin
          srv = WEBrick::HTTPServer.new({:BindAddress => '127.0.0.1',
                                        :Port => UserConfig[:rdf_port]})

          srv.mount_proc('/mikutter.xml') do |req, res|
            begin
              res.content_type = "application/xml"
              res["last-modified"] = Time.now.httpdate
              res.body = rdf_rdf.get_rdf(UserConfig[:rdf_title])
            rescue => e
              puts e
              puts e.backtrace
            end
          end

          trap("INT") do
            srv.shutdown
          end

          srv.start
        rescue => e
          puts e
          puts e.backtrace
        end
      end

    rescue => e
      puts e
      puts e.backtrace
    end
  end


  # 新ツイート時
  onupdate do |service, messages|
    begin
      messages.each do |message|
        rdf_rdf.add_message_if_needed(message)
      end

    rescue => e
      puts e
      puts e.backtrace
    end
  end
end
