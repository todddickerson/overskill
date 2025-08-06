class Integrations::GoogleOauth2Installation < ApplicationRecord
  include Integrations::GoogleOauth2Installations::Base

  def process_webhook(webhook)
    raise "You should implement a `Integrations::GoogleOauth2Installation` model in your application that has `include Integrations::GoogleOauth2Installations::Base` and implements a `def process_webhook(webhook)` method."
  end
end
