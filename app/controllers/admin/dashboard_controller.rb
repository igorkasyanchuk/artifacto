module Admin
  class DashboardController < BaseController
    def show
      @stats = Stats.new
    end
  end
end
