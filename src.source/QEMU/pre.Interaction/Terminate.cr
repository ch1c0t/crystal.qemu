def terminate : Bool
  result = false

  begin
    @context.stop
  ensure
    begin
      @context_process.terminate
    ensure
      result = @vm.terminate
    end
  end

  result
end
