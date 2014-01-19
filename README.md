# Rack Service

Use a Ruby class as a web service API.

An instance method's name becomes the URI's leading path element, the positional parameters become the remaining path elements, and the named parameters become query and body parameter values.

The named parameters may be passed either url-encoded or as JSON.  The return value will be plain text if a simple value or a value that cannot be encoded as JSON, otherwise it will be JSON.

By default, public instance methods of the API class are GET methods.  GET, POST, PUT, and DELETE methods may be defined explicitly using the `get`, `post`, `put`, and `delete` functions in the same way one uses Ruby's `public`, `protected` and `private` functions.

For example, here is a `rackup` config for a simple key-value store API:

    require './rackservice'

    class KeyValueAPI < RackService::API
      def initialize
        @db = {}
      end
      def find(key)
        @db[key]
      end
      def all
        @db
      end
      put
      def set(key, value)
        @db[key] = value
      end
      delete
      def remove(key)
        @db.delete key
      end
    end

    run KeyValueAPI.new

One could then interact with the service, e.g. with `curl`:

    % curl -X PUT localhost:9292/set/name/Alice
    Alice
    % curl localhost:9292/find/name
    Alice
    % curl localhost:9292/all
    {"name":"Alice"}
    % curl -X DELETE localhost:9292/remove/name
    Alice
    % curl localhost:9292/all
    {}
