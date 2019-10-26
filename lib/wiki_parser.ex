defmodule WikiParser do
  @moduledoc """
  Documentation for WikiParser.
  """
  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://en.wikipedia.org"
  plug Tesla.Middleware.JSON

  def search_for_game(game) do
    game =
      String.downcase(game)

    result =
      get("/w/api.php?action=query&list=search&utf8=&format=json&srprop=snippet&srsearch=#{URI.encode(game)}%20video%20game")
      |> get_search_results()
      |> filter_search_results(game)
  end

  def get_search_results({:ok, response}) do
    response
    |> Map.get(:body)
    |> Map.get("query")
    |> Map.get("search")
  end

  def filter_search_results(search_results, game) do
    filtered_results =
      search_results
      |> Enum.reject(fn result ->
        title = String.downcase(result["title"])

        !String.contains?(title, game)
      end)
      |> Enum.reject(fn result ->
        title = String.downcase(result["title"])

        if title != game do
          !String.contains?(title, "video game")
        else
          false
        end
      end)

    if length(filtered_results) > 1 do
      Enum.reject(filtered_results, fn result ->
        !String.contains?(result["title"], "video game")
      end)
    else
      filtered_results
    end
  end


end
