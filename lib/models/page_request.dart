final class PageRequest {
  final int currentPage;
  final int generation;
  final List<int> pagesToRender;

  const PageRequest(this.currentPage, this.generation, this.pagesToRender);
}
