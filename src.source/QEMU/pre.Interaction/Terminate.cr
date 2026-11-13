def terminate : Bool
  result = false

  begin
    @text_recognition.close
  ensure
    begin
      @context.stop
    ensure
      begin
        @context_process.terminate
      ensure
        result = @vm.terminate
      end
    end
  end

  result
end
