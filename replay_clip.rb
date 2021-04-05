#! /bin/ruby 

require 'optparse'
require 'tmpdir'
require 'open3'
require 'fileutils'
require 'pathname'

class FFMpegError < StandardError; end

def execute_cmd(cmd)
  puts "executing '#{cmd}'"
  cmd_output, exit_code = Open3.capture2e(cmd)
  puts "-----------\nCommand Output\n----------\n#{cmd_output}" if @debug
  puts "-----------\nExit Status\n----------\n#{exit_code}" if @debug
  raise FFMpegError if exit_code != 0
end

@options = { speed: 0.7 }
@debug = false

OptionParser.new do |opts|
  opts.on("-v SOURCE", "--video SOURCE", "Source video file") { |source| @options[:source] = source }
  opts.on("-o OUTPUT", "--output OUTPUT", "Output file name") { |output| @options[:output_name] = output }
  opts.on("-s START", "--start-time START", "Start time of video clip") { |start_time| @options[:start_time] = start_time }
  opts.on("-e END", "--end-time END", "End time of video clip") { |end_time| @options[:end_time] = end_time }
  opts.on("-S SPEED", "--speed SPEED", Float, "Slow mo replay speed. 1.0 is full speed") { |speed| @options[:speed] = speed }

  opts.on("--debug") do
    puts "debugging on"
    @debug = true
  end
end.parse!
puts @options.inspect if @debug

tmp_path = Pathname.new "/tmp/slomo"
FileUtils.mkdir tmp_path

begin
  executable = "ffmpeg"
  puts tmp_path if @debug 
  puts tmp_path.join("1.mp4") if @debug 
  
  full_speed_path = tmp_path.join("fullspeed.mp4")
  slow_speed_path = tmp_path.join("slowspeed.mp4")
  finished_path = tmp_path.join("finished.mp4")

  # cut the video clip from the longer video
  cmd = "#{executable} -i #{@options[:source]}"
  cmd << " -ss #{@options[:start_time]}"
  cmd << " -to #{@options[:end_time]}"
  # cmd << " -f h264"
  cmd << " #{full_speed_path}"
  execute_cmd(cmd)

  # create a slow motion version of the short clip
  presentation_timestamp_factor = 1/@options[:speed]
  cmd = "#{executable} -i #{full_speed_path}"
  # cmd << " -f h264"
  cmd << " -filter:v \"setpts=#{presentation_timestamp_factor}*PTS\""
  cmd << " -filter:a \"atempo=#{@options[:speed]}\""
  cmd << " #{slow_speed_path}"
  execute_cmd(cmd)

  # concatenate the two videos: fast, slow, fast, slow
  concat_file_path = tmp_path.join("concat_file.txt")
  concat_file = File.new concat_file_path, "w"
  concat_file.write("file #{full_speed_path}\n")
  concat_file.write("file #{slow_speed_path}\n")
  concat_file.write("file #{full_speed_path}\n")
  concat_file.write("file #{slow_speed_path}\n")
  concat_file.close

  puts `ls -l #{concat_file_path}` if @debug

  cmd = "#{executable} -f concat"
  cmd << " -safe 0"
  cmd << " -i #{concat_file.path}"
  cmd << " -c copy"
  # cmd << " -f h264"
  cmd << " #{finished_path}"
  execute_cmd(cmd)

  # move to output location

  cmd = "mv #{finished_path} #{@options[:output_name]}"
  execute_cmd(cmd)

  puts "finished"
ensure
  puts "deleting tmp dir" if @debug
  FileUtils.remove_entry tmp_path
end
