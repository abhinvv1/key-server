require 'rack/test'
require 'rspec'
require_relative '../api_key_server'

ENV['RACK_ENV'] = 'test'

RSpec.describe ApiKeyServer do
  include Rack::Test::Methods

  def app
    ApiKeyServer
    KeyManager
    Routes
  end

  let(:redis) { Redis.new(url: ENV['REDIS_URL']) }

  before(:each) do
    redis.flushdb
  end

  describe 'POST /keys' do
    it 'generates a new API key' do
      post '/keys'
      expect(last_response).to be_ok
      response = JSON.parse(last_response.body)
      expect(response['key']).to be_a(String)
      expect(response['key'].length).to eq(32)
    end
  end

  describe 'GET /keys/available' do
    context 'when a key is available' do
      before do
        post '/keys'
        @key = JSON.parse(last_response.body)['key']
        redis.sadd('available_keys', @key)
      end

      it 'returns an available key' do
        get '/keys/available'
        expect(last_response).to be_ok
        response = JSON.parse(last_response.body)
        expect(response['key']).to eq(@key)
      end
    end

    context 'when no key is available' do
      it 'returns a 404 error' do
        get '/keys/available'
        expect(last_response.status).to eq(404)
        response = JSON.parse(last_response.body)
        expect(response['error']).to eq('No available keys')
      end
    end
  end

  describe 'PATCH /keys/:key/unblock' do
    before do
      post '/keys'
      @key = JSON.parse(last_response.body)['key']
      redis.setex("blocked:#{@key}", 60, 'blocked')
    end

    it 'unblocks a key' do
      redis.setex("#{Constants::KEY_PREFIX}#{@key}", Constants::EXPIRY_TIME, 'available')
      redis.zadd(Constants::BLOCKED_KEYS_SORTED_SET, Time.now.to_i + Constants::BLOCK_TIME, @key)

      patch "/keys/#{@key}/unblock"

      expect(last_response).to be_ok
      response = JSON.parse(last_response.body)
      expect(response['message']).to eq('Key unblocked')
      expect(redis.zscore(Constants::BLOCKED_KEYS_SORTED_SET, @key)).to be_nil
      expect(redis.sismember(Constants::AVAILABLE_KEYS, @key)).to be true
      expect(redis.exists?("#{Constants::KEY_PREFIX}#{@key}")).to be true
    end
  end

  describe 'DELETE /keys' do
    before do
      post '/keys'
      @key = JSON.parse(last_response.body)['key']
    end

    it 'deletes a key' do
      delete '/keys', key: @key
      expect(last_response).to be_ok
      response = JSON.parse(last_response.body)
      expect(response['message']).to eq('Key deleted')
      expect(redis.exists?("api_key:#{@key}")).to be_falsey
    end

    it 'returns a 404 error when trying to delete a non-existent key or bad key' do
      delete '/keys', key: 'non_existent_key'
      expect(last_response.status).to eq(404)
      response = JSON.parse(last_response.body)
      expect(response['error']).to eq('Key not found')
    end
  end

  describe 'POST /keys/:key/keep_alive' do
    before do
      post '/keys'
      @key = JSON.parse(last_response.body)['key']
    end

    it 'keeps a key alive' do
      post "/keys/#{@key}/keep_alive"
      expect(last_response).to be_ok
      response = JSON.parse(last_response.body)
      expect(response['message']).to eq('Key kept alive')
    end
  end
end
