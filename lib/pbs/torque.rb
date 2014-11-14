#
# Copyright (C) 2014 Jeremy Nicklas
#
# This file is part of ruby-ffi.
#
# All rights reserved.
#

require 'ffi'

module PBS
  extend FFI::Library
  ffi_lib 'torque'

  # int pbs_errno /* error number */
  attach_variable :_pbs_errno, :pbs_errno, :int

  # int pbs_connect(char *server)
  attach_function :_pbs_connect, :pbs_connect, [ :pointer ], :int

  # char *pbs_default(void);
  attach_function :_pbs_default, :pbs_default, [], :string
  
  # int pbs_deljob(int connect, char *job_id, char *extend)
  attach_function :_pbs_deljob, :pbs_deljob, [ :int, :pointer, :pointer ], :int

  # int pbs_disconnect(int connect)
  attach_function :_pbs_disconnect, :pbs_disconnect, [ :int ], :int

  # void pbs_statfree(struct batch_status *stat)
  attach_function :_pbs_statfree, :pbs_statfree, [ :pointer ], :void

  # batch_status * pbs_statjob(int connect, char *id, struct attrl *attrib, char *extend)
  attach_function :_pbs_statjob, :pbs_statjob, [ :int, :pointer, :pointer, :pointer ], :pointer

  # batch_status * pbs_statnode(int connect, char *id, struct attrl *attrib, char *extend)
  attach_function :_pbs_statnode, :pbs_statnode, [ :int, :pointer, :pointer, :pointer ], :pointer

  # batch_status * pbs_statque(int connect, char *id, struct attrl *attrib, char *extend)
  attach_function :_pbs_statque, :pbs_statque, [ :int, :pointer, :pointer, :pointer ], :pointer

  # batch_status * pbs_statserver(int connect, struct attrl *attrib, char *extend)
  attach_function :_pbs_statserver, :pbs_statserver, [ :int, :pointer, :pointer ], :pointer

  # char *pbs_submit(int connect, struct attropl *attrib, char *script, char *destination, char *extend)
  attach_function :_pbs_submit, :pbs_submit, [ :int, :pointer, :pointer, :pointer, :pointer ], :string

  class << self
    alias_method :pbs_default, :_pbs_default
    alias_method :pbs_disconnect, :_pbs_disconnect
    alias_method :pbs_statfree, :_pbs_statfree

    def pbs_connect(*args)
      tmp = _pbs_connect(*args)
      raise PBSError, "#{error}" if error?
      tmp
    end

    def pbs_deljob(*args)
      tmp = _pbs_deljob(*args)
      raise PBSError, "#{error}" if error?
      tmp
    end

    # Request status of jobs with defined parameters
    # Then converts C-linked list pointers to Ruby arrays
    %w{pbs_statjob pbs_statnode pbs_statque pbs_statserver}.each do |method|
      define_method(method) do |*args|
        jobs_ptr = send(method.prepend("_").to_sym, *args)
        raise PBSError, "#{error}" if error?
        jobs = jobs_ptr.read_array_of_type(BatchStatus)
        jobs.each do |job|
          job[:attribs] = job[:attribs].read_array_of_type(Attrl)
        end
        _pbs_statfree(jobs_ptr) # free memory
        jobs
      end
    end

    def pbs_submit(connect, attropl_list, script, destination, extends)

      attropl_list = [attropl_list] unless attropl_list.is_a? Array

      prev = FFI::Pointer.new(FFI::Pointer::NULL)
      attropl_list.each do |attropl_hash|
        attropl = Attropl.new
        attropl[:name] = FFI::MemoryPointer.from_string(attropl_hash[:name] || "")
        attropl[:resource] = FFI::MemoryPointer.from_string(attropl_hash[:resource] || "")
        attropl[:value] = FFI::MemoryPointer.from_string(attropl_hash[:value] || "")
        attropl[:op] = :set
        attropl[:next] = prev
        prev = attropl
      end

      tmp = _pbs_submit(connect, prev, script, destination, extends)
      raise PBSError, "#{error}" if error?
      tmp
    end

    def error?
      !_pbs_errno.zero?
    end

    def error
      ERRORS_TXT[_pbs_errno] || "Could not find a text for this error."
    end
  end

  BatchOp = enum( :set, :unset, :incr, :decr, :eq, :ne, :ge,
                  :gt, :le, :lt, :dflt, :merge )

  class Attrl < FFI::Struct
    layout :next,       :pointer,
           :name,       :string,
           :resource,   :string,
           :value,      :string,
           :op,         BatchOp         # not used
  end

  class Attropl < FFI::Struct
    layout :next,       :pointer,
           :name,       :pointer,
           :resource,   :pointer,
           :value,      :pointer,
           :op,         BatchOp
  end

  class BatchStatus < FFI::Struct
    layout :next,       :pointer,
           :name,       :string,
           :attribs,    :pointer,       # struct attrl*
           :text,       :string
  end

  class FFI::Pointer
    def read_array_of_type(type)
      ary = []
      ptr = self
      until ptr.null?
        tmp = type.new(ptr)
        ary << Hash[tmp.members.zip(tmp.members.map {|key| tmp[key]})]
        ptr = tmp[:next]
      end
      ary
    end
  end
end
