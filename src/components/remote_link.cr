struct RemoteLink
  def initialize(@url : URI)
  end

  def to_s(io)
    io << %{<a href="}
    @url.to_s io
    io << %{" style="display: inline-block; transform: rotate(-90deg)">⤵️</a>}
  end
end
