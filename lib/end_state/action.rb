module EndState
  class Action
    attr_reader :object, :state

    def initialize(object, state)
      @object = object
      @state = state
    end

    def call
      object.state = object.class.store_states_as_strings ? state.to_s : state.to_sym
      true
    end

    def rollback
      call
    end
  end
end
