defmodule Scenic.Component.Input.Slider do
  use Scenic.Component, has_children: false

  alias Scenic.Graph
  alias Scenic.ViewPort
  alias Scenic.Utilities.Draw.Color
  import Scenic.Primitives, only: [{:rect, 3}, {:line, 3}, {:rrect, 3}, {:update_opts,2}]


  @height             16
  @mid_height         trunc(@height / 2)
  @radius             5
  @btn_size           14
  @line_width         4

  @default_width      300

  # type is {line_color, thumb_color}
  @colors %{
    light:    {:cornflower_blue, :black},
    dark:     {:cornflower_blue, :antique_white},
  }

#  #--------------------------------------------------------
  def info() do
    "#{IO.ANSI.red()}Slider data must be: {extents, initial, id, opts \\\\ []}" <>
    IO.ANSI.yellow() <>
    "\r\n" <>
    IO.ANSI.default_color()
  end



  #--------------------------------------------------------
  def verify( {ext, initial, id} ), do: verify( {ext, initial, id, []} )
  def verify( {ext, initial, _id, opts} = data ) when is_list(opts) do
    opts
    |> Enum.all?( &verify_option(&1) ) && verify_initial(ext, initial)
    |> case do
      true -> {:ok, data}
      _ -> :invalid_data
    end
  end
  def verify( _ ), do: :invalid_data

  #--------------------------------------------------------
  defp verify_initial({min,max}, init) when is_integer(min) and is_integer(max) and
  is_integer(init) and init >= min and init <= max, do: true
  defp verify_initial({min,max}, init) when is_float(min) and is_float(max) and
  is_number(init) and init >= min and init <= max, do: true
  defp verify_initial( list_ext, init ) when is_list(list_ext), do: Enum.member?(list_ext, init)
  defp verify_initial( _, _ ), do: false

  #--------------------------------------------------------
  defp verify_option( {:type, :light} ), do: true
  defp verify_option( {:type, :dark} ), do: true
  defp verify_option( {:type, {line_color, thumb_color}} ) do
    Color.verify( line_color ) &&
    Color.verify( thumb_color )
  end
  defp verify_option( _ ), do: false

  #--------------------------------------------------------
  # def valid?( {_ext, _init, _width, _id} ), do: true
  # def valid?( _d ), do: false


  #--------------------------------------------------------
  def init( {extents, value, id}, args ), do: init( {extents, value, id, []}, args )
  def init( {extents, value, id, opts}, _args ) do
    colors = case opts[:type] do
      {_,_} = colors -> colors
      type -> Map.get(@colors, type) || Map.get(@colors, :dark)
    end
    {line_color, thumb_color} = colors

    width = opts[:width] || opts[:w] || @default_width


    graph = Graph.build()
      |> rect( {width, @height}, fill: :clear )
      |> line( {{0,@mid_height},{width,@mid_height}}, stroke: {@line_width, line_color} )
      |> rrect( {@btn_size, @btn_size, @radius}, fill: thumb_color, id: :thumb, t: {0,1} )
      |> update_slider_position( value, extents, width )

    state = %{
      graph: graph,
      value: value,
      extents: extents,
      width: width,
      id: id,
      tracking: false
    }

    push_graph( graph )

    {:ok, state}
  end

  #--------------------------------------------------------
  def handle_input( {:cursor_button, {:left, :press, _, {x,_}}}, context, state ) do
    state = state
    |> Map.put( :tracking, true )

    state = update_slider( x, state )

    ViewPort.capture_input(context, [:cursor_button, :cursor_pos])

    {:noreply, state} #%{state | graph: graph}}
  end

  #--------------------------------------------------------
  def handle_input( {:cursor_button, {:left, :release, _, _}}, context, state ) do
    state = Map.put(state, :tracking, false)

    ViewPort.release_input( context, [:cursor_button, :cursor_pos])

    {:noreply, state} #%{state | graph: graph}}
  end


  #--------------------------------------------------------
  def handle_input( {:cursor_pos, {x,_}}, _context, %{tracking: true} = state ) do
    state = update_slider( x, state )
    {:noreply, state}
  end


  #--------------------------------------------------------
  def handle_input( _event, _context, state ) do
    {:noreply, state}
  end


  #============================================================================
  # internal utilities
  # {text_color, box_background, border_color, pressed_color, checkmark_color}

  defp update_slider( x, %{
    graph: graph,
    value: old_value,
    extents: extents,
    width: width,
    id: id,
    tracking: true
  } = state ) do

    # pin x to be inside the width
    x = cond do
      x < 0     -> 0
      x > width -> width
      true -> x
    end

    # calc the new value based on it's position across the slider
    new_value = calc_value_by_percent(extents, x / width)

    # update the slider position
    graph = update_slider_position(graph, new_value, extents, width)

    if new_value != old_value do
      send_event({:value_changed, id, new_value})
    end

    %{ state |
      graph: graph,
      value: new_value
    }
  end

  #--------------------------------------------------------
  defp update_slider_position(graph, new_value, extents, width) do
    # calculate the slider position
    new_x = calc_slider_position( width, extents, new_value )

    # apply the x position
    Graph.modify(graph, :thumb, fn(p) ->
      #Primitive.put_transform( p, :translate, {x,0} )
      # { {_, y}, width, height, radius } = Primitive.get(p)
      # Primitive.put(p, { {new_x, y}, width, height, radius })    
      update_opts(p, translate: {new_x, 0})
    end)
    |> push_graph()
  end

  #--------------------------------------------------------
  # calculate the position if the extents are numeric
  defp calc_slider_position(width, extents, value)
  defp calc_slider_position(width, {min,max}, value) when value < min do
    calc_slider_position(width, {min,max}, min)
  end
  defp calc_slider_position(width, {min,max}, value) when value > max do
    calc_slider_position(width, {min,max}, max)
  end
  defp calc_slider_position(width, {min,max}, value) do
    width = width - @btn_size
    percent = (value - min) / (max - min)
    trunc( width * percent )
  end

  #--------------------------------------------------------
  # calculate the position if the extents is a list of arbitrary values
  defp calc_slider_position(width, extents, value)
  defp calc_slider_position(width, ext, value) when is_list(ext) do
    max_index = Enum.count(ext) - 1

    index = case Enum.find_index(ext, fn(v) -> v == value end) do
      nil ->    raise "Slider value not in extents list"
      index ->  index
    end

    # calc position of slider
    width = width - @btn_size
    percent = index / max_index
    round( width * percent )
  end

  #--------------------------------------------------------
  defp calc_value_by_percent({min,max}, percent) when is_integer(min) and is_integer(max) do
    round((max - min) * percent) + min
  end

  defp calc_value_by_percent({min,max}, percent)when is_float(min) and is_float(max) do
    ((max - min) * percent) + min
  end

  defp calc_value_by_percent(extents, percent) when is_list(extents) do
    max_index = Enum.count(extents) - 1
    index = round(max_index * percent)
    Enum.at(extents, index)
  end


end










