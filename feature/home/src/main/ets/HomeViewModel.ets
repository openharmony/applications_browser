/** 主页 ViewModel：搜索模式状态 */
@Observed
export class HomeViewModel {
  isSearchMode: boolean = false
  searchQuery: string = ''

  enterSearchMode(): void {
    this.isSearchMode = true
  }

  exitSearchMode(): void {
    this.isSearchMode = false
    this.searchQuery = ''
  }
}
