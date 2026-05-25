Rails.application.config.session_store :cookie_store,
  key: "_mesa_test_hub_session",
  expire_after: 2.weeks,
  secure: Rails.env.production?
