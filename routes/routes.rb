# frozen_string_literal: true

require 'sinatra/base'
require './key_manager'
require 'json'

class Routes < Sinatra::Base
  before do
    content_type :json
  end

  def initialize(app = nil)
    super(app)
    @key_manager = KeyManager.new
  end

  post '/keys' do
    key = @key_manager.generate_key
    { message: "successfully generated new key", key: key}.to_json
  end

  get '/keys/available' do
    key = @key_manager.get_available_key
    if key
      { key: key }.to_json
    else
      status 404
      { error: 'No available keys' }.to_json
    end
  end

  patch '/keys/:key/unblock' do
    key = params[:key]
    if @key_manager.unblock_key(key)
      { message: 'Key unblocked' }.to_json
    else
      status 404
      { error: 'Key not found' }.to_json
    end
  end

  delete '/keys' do
    key = params[:key]
    if @key_manager.delete_key(key)
      { message: 'Key deleted' }.to_json
    else
      status 404
      { error: 'Key not found' }.to_json
    end
  end

  post '/keys/:key/keep_alive' do
    key = params[:key]
    if @key_manager.keep_alive(key)
      { message: 'Key kept alive' }.to_json
    else
      status 404
      { error: 'Key not found' }.to_json
    end
  end
end
