class CurrentMarketplaceAppender
  def initialize(app)
    @app = app
  end

  def call(env)
    app_domain = URLUtils.strip_port_from_host(APP_CONFIG.domain)
    host = env['HTTP_HOST'].sub(/:\d+$/, '')
    marketplace = CurrentMarketplaceResolver.resolve_from_host(host, app_domain)
    @app.call(env.merge!(current_marketplace: marketplace))
  end
end
