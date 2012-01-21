# Alex's extensions to Kernel
# Kernel defines various methods for input/output, system calls, etc (like "puts")
# It is included by every object, so it makes a logical place to put functions which 
#   should be available everywhere

module Kernel

  #***************
  # ERROR HANDLING
  #***************
  
  # NAME: retry_on_exception
  # DESC: execute block
  #       if it throws an exception, try executing it again, up to "times" times
  #       if it still throws an exception, allow the exception to propagate to caller
  # NOTE: this is useful for things like sending/receiving data over a network,
  #         which may randomly fail on occasion
  #       initialize your I/O objects INSIDE the block, because they may become
  #         unusable after throwing an exception!
  #       (I once had a problem where an application was locking up, because I was 
  #        trying to retry an I/O call after an exception, using the same I/O object)
  def retry_on_exception(times)
    begin
      yield
    rescue Exception
      times -= 1
      times > 0 ? retry : raise
    end
  end

  # NAME: retry_if_nil
  # DESC: execute block up to "times" times, retrying if it returns nil
  def retry_if_nil(times)
    begin
      result = yield
    end while result.nil? && ((times -= 1) > 0)
    result
  end

  # NAME: retry_times
  # DESC: combination of "retry_on_exception" and "retry_if_nil"
  def retry_times(times)
    begin
      begin
        result = yield
      end while result.nil? && ((times -= 1) > 0)
      result
    rescue Exception
      times -= 1
      times > 0 ? retry : raise
    end
  end
end
