require 'dotenv/load'
require 'sinatra'
require './routes/routes'
require './key_manager'

class ApiKeyServer < Sinatra::Base

  use Routes

  Thread.new { KeyManager.new.manage_keys }

  run! if __FILE__ == $0 # similar to python, $0 is a global variable in Ruby that contains the name of the script being executed.
end


