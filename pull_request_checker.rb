# encoding: utf-8

require 'uri'
require 'net/http'
require 'json'

url = ENV['URL'] || 'https://api.github.com/repos/rails/rails/pulls'
$token = ENV['OAUTH']

def fetch_url url
  uri = URI(url)
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "token #{$token}" if $token
  http = Net::HTTP.new(uri.hostname, uri.port)
  http.use_ssl = (uri.scheme == 'https')
  http.request(req)
end

def parse_url url
  res = fetch_url(url)
  JSON.parse(res.body)
end

def process_commits url
  commits = parse_url(url)
  if commits.length > 1
    puts "Pull request: #{url}"
    parsed_commits = commits.inject([]) do |parsed_commits, commit|
      parsed_commits << parse_url(commit['url'])
    end
    process_files(parsed_commits)
  end
end

def process_pull_requests url
  res = fetch_url(url)
  header = res.each_header.to_h
  next_link = header['link'].split(',').inject('') do |link, pager|
    if match = /<(.+)>.*(next)/.match(pager)
      link = match[1]
    end
    link
  end
  pulls = JSON.parse(res.body)
  pulls.each do |pull|
    process_commits(pull['commits_url'])
  end
  process_pull_requests(next_link) unless next_link == ''
end

def process_files commits
  commits.inject({}) do |files, commit|
    commit['files'].each do |file|
      patch = file['patch']
      if patch
        lines = patch.split("\n")
        delete_row = 0
        add_row = 0
        if former_added_rows = files[file['filename']]
          deleted_rows = []
          new_added_rows = {}
          lines.each do |current_line|
            case current_line[0]
            when '-'
              deleted_rows << delete_row
              delete_row +=1
            when '+'
              new_added_rows[add_row] = "#{file['blob_url']}#L#{add_row}"
              add_row += 1
            when '@'
              match = (/@@\s-(\d+),?\d*\s\+(\d+),?\d*\s@@/.match(current_line))
              delete_row = match[1].to_i
              add_row = match[2].to_i
            else
              delete_row += 1
              add_row += 1
            end
          end
          former_add_rows = former_added_rows.keys
          double_touched_rows = former_add_rows & deleted_rows
          double_touched_rows.each do |row|
            File.open('rows.txt', 'a') do |f|
              puts former_added_rows[row]
              f.puts(former_added_rows[row])
            end
          end
          old_rows = {}
          new_rows = new_added_rows.keys
          no_touched_rows = former_add_rows - deleted_rows
          no_touched_rows.each do |no_touched_row|
            old_rows[no_touched_row] = no_touched_row
            new_rows.each do |new_row|
              if new_row < no_touched_row
                old_rows[no_touched_row] += 1
              end
            end
            deleted_rows.each do |deleted_row|
              if deleted_row < no_touched_row
                old_rows[no_touched_row] -= 1
              end
            end
          end
          recalculated_rows = {}
          old_rows.each_pair do |original_row, recalculated_row|
            recalculated_rows[recalculated_row] = former_added_rows[original_row]
          end
          files[file['filename']] = recalculated_rows.merge(new_added_rows)
        else
          added_rows = files[file['filename']] = {}
          lines.each do |current_line|
            case current_line[0]
            when '-'
              #
            when '+'
              added_rows[add_row] = "#{file['blob_url']}#L#{add_row}"
              add_row += 1
            when '@'
              match = (/@@\s-(\d+),?\d*\s\+(\d+),?\d*\s@@/.match(current_line))
              add_row = match[2].to_i
            else
              add_row += 1
            end
          end
        end
      end
    end
    files
  end
end

process_pull_requests(url)

