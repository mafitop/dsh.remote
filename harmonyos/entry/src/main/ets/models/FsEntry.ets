/**
 * 主机目录列表（GET /fs/list 的解析结果）。
 *
 * 新建工作区时要选的是「网关所在电脑」上的目录，不是手机本地目录，
 * 所以走网关的 /fs/list 浏览，而不是系统文件选择器。
 * 网关只允许 FS_ROOTS 之下的路径（见 gateway.js fsResolve / fsRealChecked），
 * 因此这里的 roots 就是可浏览的根。
 */
export class FsEntry {
  name: string
  path: string
  type: string

  constructor(name: string, path: string, type: string) {
    this.name = name
    this.path = path
    this.type = type
  }

  isDir(): boolean {
    return this.type === 'dir'
  }

  static fromRecord(r: Record<string, Object>): FsEntry {
    return new FsEntry(
      String(r['name'] ?? ''),
      String(r['path'] ?? ''),
      String(r['type'] ?? 'file')
    )
  }
}

export class DirListing {
  /** 服务端归一化后的绝对路径（可能是 ''，表示未取到） */
  path: string = ''
  /** 允许浏览的根目录 */
  roots: string[] = []
  /** 该目录下的条目（已按目录优先、名称排序） */
  entries: FsEntry[] = []

  static fromRecord(v: Record<string, Object>): DirListing {
    const out = new DirListing()
    out.path = String(v['path'] ?? '')
    const roots = v['roots'] as Array<Object> | undefined
    if (roots !== undefined) {
      for (const r of roots) {
        out.roots.push(String(r))
      }
    }
    const entries = v['entries'] as Array<Record<string, Object>> | undefined
    if (entries !== undefined) {
      for (const e of entries) {
        out.entries.push(FsEntry.fromRecord(e))
      }
    }
    return out
  }

  /** 只要子目录 */
  dirs(): FsEntry[] {
    const list: FsEntry[] = []
    for (const e of this.entries) {
      if (e.isDir()) {
        list.push(e)
      }
    }
    return list
  }
}

/** 上一级目录；已是根返回 ''（调用方据此隐藏「上级」） */
export function parentPathOf(path: string): string {
  if (path.length === 0) {
    return ''
  }
  const t = path.endsWith('/') ? path.slice(0, -1) : path
  const i = t.lastIndexOf('/')
  if (i < 0) {
    return ''
  }
  if (i === 0) {
    return '/'
  }
  return t.slice(0, i)
}

/** 路径最后一段（用于列表里显示「到上一级」或标签） */
export function lastSegmentOf(path: string): string {
  if (path.length === 0) {
    return ''
  }
  const t = path.endsWith('/') ? path.slice(0, -1) : path
  const i = t.lastIndexOf('/')
  return i < 0 ? t : t.slice(i + 1)
}
