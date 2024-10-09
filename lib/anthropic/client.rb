module Anthropic
  class Client
    include Anthropic::HTTP

    CONFIG_KEYS = %i[
      access_token
      anthropic_version
      api_version
      uri_base
      request_timeout
      extra_headers
    ].freeze

    def initialize(config = {}, &faraday_middleware)
      CONFIG_KEYS.each do |key|
        # Set instance variables like api_type & access_token. Fall back to global config
        # if not present.
        instance_variable_set(
          "@#{key}",
          config[key].nil? ? Anthropic.configuration.send(key) : config[key]
        )
      end
      @faraday_middleware = faraday_middleware
    end

    # @deprecated (but still works while Anthropic API responds to it)
    def complete(parameters: {})
      parameters[:prompt] = wrap_prompt(prompt: parameters[:prompt])
      json_post(path: "/complete", parameters: parameters)
    end

    # Anthropic API Parameters as of 2024-05-07:
    #   @see https://docs.anthropic.com/claude/reference/messages_post
    #
    # @param [Hash] parameters
    # @option parameters [Array] :messages - Required. An array of messages to send to the API. Each
    #   message should have a role and content. Single message example:
    #   +[{ role: "user", content: "Hello, Claude!" }]+
    # @option parameters [String] :model - see https://docs.anthropic.com/claude/docs/models-overview
    # @option parameters [Integer] :max_tokens - Required, must be less than 4096 - @see https://docs.anthropic.com/claude/docs/models-overview
    # @option parameters [String] :system - Optional but recommended. @see https://docs.anthropic.com/claude/docs/system-prompts
    # @option parameters [Float] :temperature - Optional, defaults to 1.0
    # @option parameters [Proc] :stream - Optional, if present, must be a Proc that will receive the
    #   content fragments as they come in
    # @option parameters [String] :preprocess_stream - If true, the streaming Proc will be pre-
    #   processed. Specifically, instead of being passed a raw Hash like:
    #   {"type"=>"content_block_delta", "index"=>0, "delta"=>{"type"=>"text_delta", "text"=>" of"}}
    #   the Proc will instead be passed something nicer. If +preprocess_stream+ is set to +"json"+
    #   or +:json+, then the Proc will only receive full json objects, one at a time.
    #   If +preprocess_stream+ is set to +"text"+ or +:text+ then the Proc will receive two
    #   arguments: the first will be the text accrued so far, and the second will be the delta
    #   just received in the current chunk.
    #
    # @returns [Hash] the response from the API (after the streaming is done, if streaming)
    #   @example:
    # {
    #   "id" => "msg_013xVudG9xjSvLGwPKMeVXzG",
    #   "type" => "message",
    #   "role" => "assistant",
    #   "content" => [{"type" => "text", "text" => "The sky has no distinct"}],
    #   "model" => "claude-2.1",
    #   "stop_reason" => "max_tokens",
    #   "stop_sequence" => nil,
    #   "usage" => {"input_tokens" => 15, "output_tokens" => 5}
    # }
    def messages(parameters: {})
      json_post(path: "/messages", parameters: parameters)
    end

    # Anthropic API Parameters as of 2024-10-09:
    #   @see https://docs.anthropic.com/en/api/creating-message-batches
    #
    # @param [Array] :requests - List of requests for prompt completion. Each is an individual request to create a Message.
    #   Requests are an array of hashes, each with the following keys:
    #   - :custom_id (required): Developer-provided ID created for each request in a Message Batch.
    #                            Useful for matching results to requests, as results may be given out of request order.
    #                            Must be unique for each request within the Message Batch.
    #   - :params (required): Messages API creation parameters for the individual request.
    #                            See the Messages API reference for full documentation on available parameters.
    #
    # @returns [Hash] the response from the API (after the streaming is done, if streaming)
    #   @example:
    # {
    #   "id"=>"msgbatch_01668jySCZeCpMLsxFcroNnN",
    #   "type"=>"message_batch",
    #   "processing_status"=>"in_progress",
    #   "request_counts"=>{"processing"=>2, "succeeded"=>0, "errored"=>0, "canceled"=>0, "expired"=>0},
    #   "ended_at"=>nil,
    #   "created_at"=>"2024-10-09T20:18:11.480471+00:00",
    #   "expires_at"=>"2024-10-10T20:18:11.480471+00:00",
    #   "cancel_initiated_at"=>nil,
    #   "results_url"=>nil
    # }
    def batch_messages(requests_parameters)
      # required to use the Batch API. https://docs.anthropic.com/en/docs/build-with-claude/message-batches
      custom_headers = { "anthropic-beta" => "message-batches-2024-09-24" }
      json_post(path: "/messages/batches", parameters: { "requests" => requests_parameters }, custom_headers:)
    end

    # allows using the batch API via `client.messages.batch` method.
    def messages
      MessagesBatcher.new(self)
    end

    class MessagesBatcher
      def initialize(client)
        @client = client
      end

      def batch(requests_parameters)
        @client.batch_messages(requests_parameters)
      end
    end

    private

    # Used only by @deprecated +complete+ method
    def wrap_prompt(prompt:, prefix: "\n\nHuman: ", suffix: "\n\nAssistant:")
      return if prompt.nil?

      prompt.prepend(prefix) unless prompt.start_with?(prefix)
      prompt.concat(suffix) unless prompt.end_with?(suffix)
      prompt
    end
  end
end
