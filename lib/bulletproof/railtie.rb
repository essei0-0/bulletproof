# frozen_string_literal: true

module Bulletproof
  class Railtie < Rails::Railtie
    # config/initializers が読まれた後にミドルウェアを挿入する。
    # これにより、ユーザーが initializer 内で設定した値が反映される。
    initializer "bulletproof.insert_middleware", after: :load_config_initializers do |app|
      app.middleware.use Bulletproof::Middleware if Bulletproof.config.enabled
    end
  end
end
