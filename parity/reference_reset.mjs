export async function resetReferenceState (overlayTextureIds = []) {
  const p = window.__noisemakerRenderingPipeline
  const backend = p?.backend
  if (!p) return { error: 'no pipeline' }
  if (!backend?.textures || typeof backend.clearTexture !== 'function') {
    return { error: 'backend cannot clear textures' }
  }
  if (overlayTextureIds.length) {
    if (typeof p.whenAsyncInitsSettled !== 'function') {
      return { error: 'pipeline cannot wait for async overlays' }
    }
    await p.whenAsyncInitsSettled()
    if (!Array.isArray(window.__nmAsyncInitErrors)) {
      return { error: 'async overlay error capture unavailable' }
    }
    if (window.__nmAsyncInitErrors.length) {
      return { error: `async overlay failed: ${window.__nmAsyncInitErrors.join('; ')}` }
    }
    const gl = backend.gl
    if (!gl) return { error: 'backend cannot inspect async overlays' }
    for (const texId of overlayTextureIds) {
      const tex = backend.textures.get(texId)
      if (!tex?.handle || !tex.width || !tex.height) {
        return { error: `missing async overlay ${texId}` }
      }
      const previousFbo = gl.getParameter(gl.FRAMEBUFFER_BINDING)
      const fbo = gl.createFramebuffer()
      if (!fbo) return { error: `cannot inspect async overlay ${texId}` }
      let hasPixels = false
      try {
        gl.bindFramebuffer(gl.FRAMEBUFFER, fbo)
        gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex.handle, 0)
        if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) {
          return { error: `incomplete async overlay ${texId}` }
        }
        const pixels = new Uint8Array(tex.width * tex.height * 4)
        gl.readPixels(0, 0, tex.width, tex.height, gl.RGBA, gl.UNSIGNED_BYTE, pixels)
        for (let i = 3; i < pixels.length; i += 4) {
          if (pixels[i] !== 0) {
            hasPixels = true
            break
          }
        }
      } finally {
        gl.bindFramebuffer(gl.FRAMEBUFFER, previousFbo)
        gl.deleteFramebuffer(fbo)
      }
      if (!hasPixels) return { error: `blank async overlay ${texId}` }
    }
  }

  const preserved = new Set(overlayTextureIds)
  const textureIds = [...backend.textures.keys()]
  let clearedTextureCount = 0
  for (const texId of textureIds) {
    if (!preserved.has(texId)) {
      backend.clearTexture(texId)
      clearedTextureCount++
    }
  }
  const normalizedSurfaces = []
  if (p.surfaces) {
    for (const [name, surface] of p.surfaces.entries()) {
      const readId = `global_${name}_read`
      const writeId = `global_${name}_write`
      if (backend.textures.get(readId) && backend.textures.get(writeId)) {
        surface.read = readId
        surface.write = writeId
        normalizedSurfaces.push(name)
      }
    }
  }
  p.frameIndex = 0
  p.lastTime = 0
  return { textureCount: clearedTextureCount, normalizedSurfaces }
}
