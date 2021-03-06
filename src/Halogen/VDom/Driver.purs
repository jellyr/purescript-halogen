module Halogen.VDom.Driver
  ( runUI
  , module Halogen.Aff.Driver
  ) where

import Prelude

import Control.Monad.Aff (Aff)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Class (liftEff)

import Data.Foldable (traverse_)
import Data.Maybe (Maybe(..))
import Data.Nullable (toMaybe)

import DOM (DOM)
import DOM.HTML (window) as DOM
import DOM.HTML.Types (HTMLElement, htmlElementToNode, htmlDocumentToDocument) as DOM
import DOM.HTML.Window (document) as DOM
import DOM.Node.Node (appendChild, removeChild, parentNode, nextSibling, insertBefore) as DOM
import DOM.Node.Types (Document, Element, Node) as DOM

import Halogen.Aff.Driver (HalogenIO)
import Halogen.Aff.Driver as AD
import Halogen.Aff.Driver.State (RenderStateX, unRenderStateX)
import Halogen.Aff.Effects (HalogenEffects)
import Halogen.Component (Component, ComponentSlot)
import Halogen.HTML.Core (HTML(..), Prop)
import Halogen.Query.InputF (InputF)
import Halogen.VDom as V
import Halogen.VDom.DOM.Prop as VP

type VHTML f g p eff =
  V.VDom (Array (Prop (InputF Unit (f Unit)))) (ComponentSlot HTML g (Aff (HalogenEffects eff)) p (f Unit))

newtype RenderState s f g p o eff =
  RenderState
    { node :: DOM.Node
    , machine :: V.Step (Eff (HalogenEffects eff)) (VHTML f g p eff) DOM.Node
    }

mkSpec
  :: forall f g p eff
   . (InputF Unit (f Unit) -> Eff (HalogenEffects eff) Unit)
  -> (ComponentSlot HTML g (Aff (HalogenEffects eff)) p (f Unit) -> Eff (HalogenEffects eff) (RenderStateX RenderState eff))
  -> DOM.Document
  -> V.VDomSpec
      (HalogenEffects eff)
      (Array (VP.Prop (InputF Unit (f Unit))))
      (ComponentSlot HTML g (Aff (HalogenEffects eff)) p (f Unit))
mkSpec handler renderChild document =
  V.VDomSpec { buildWidget, buildAttributes, document }
  where

  buildAttributes
    :: DOM.Element
    -> V.VDomMachine (HalogenEffects eff) (Array (VP.Prop (InputF Unit (f Unit)))) Unit
  buildAttributes = VP.buildProp handler

  buildWidget
    :: V.VDomSpec (HalogenEffects eff)
          (Array (VP.Prop (InputF Unit (f Unit))))
          (ComponentSlot HTML g (Aff (HalogenEffects eff)) p (f Unit))
    -> V.VDomMachine (HalogenEffects eff)
          (ComponentSlot HTML g (Aff (HalogenEffects eff)) p (f Unit))
          DOM.Node
  buildWidget spec slot = do
    rsx <- renderChild slot
    let node = unRenderStateX (\(RenderState { node }) -> node) rsx
    pure (V.Step node patch done)

  patch
    :: V.VDomMachine (HalogenEffects eff)
          (ComponentSlot HTML g (Aff (HalogenEffects eff)) p (f Unit))
          DOM.Node
  patch slot = do
    rsx <- renderChild slot
    let node = unRenderStateX (\(RenderState { node }) -> node) rsx
    pure (V.Step node patch done)

  done :: Eff (HalogenEffects eff) Unit
  done = pure unit

runUI
  :: forall f eff i o
   . Component HTML f i o (Aff (HalogenEffects eff))
  -> i
  -> DOM.HTMLElement
  -> Aff (HalogenEffects eff) (HalogenIO f o (Aff (HalogenEffects eff)))
runUI component i element = do
  document <- liftEff $ DOM.htmlDocumentToDocument <$> (DOM.document =<< DOM.window)
  AD.runUI (renderSpec document element) component i

renderSpec
  :: forall eff
   . DOM.Document
  -> DOM.HTMLElement
  -> AD.RenderSpec HTML RenderState eff
renderSpec document container = { render, renderChild: id, removeChild }
  where

  render
    :: forall s f g p o
     . (forall x. InputF x (f x) -> Eff (HalogenEffects eff) Unit)
    -> (ComponentSlot HTML g (Aff (HalogenEffects eff)) p (f Unit) -> Eff (HalogenEffects eff) (RenderStateX RenderState eff))
    -> HTML (ComponentSlot HTML g (Aff (HalogenEffects eff)) p (f Unit)) (f Unit)
    -> Maybe (RenderState s f g p o eff)
    -> Eff (HalogenEffects eff) (RenderState s f g p o eff)
  render handler child (HTML vdom) =
    case _ of
      Nothing -> do
        let spec = mkSpec handler child document
        machine <- V.buildVDom spec vdom
        let node = V.extract machine
        DOM.appendChild node (DOM.htmlElementToNode container)
        pure $ RenderState { machine, node }
      Just (RenderState { machine, node }) -> do
        parent <- DOM.parentNode node
        nextSib <- DOM.nextSibling node
        machine' <- V.step machine vdom
        let newNode = V.extract machine'
        when (not nodeRefEq node newNode) do
          substInParent newNode (toMaybe nextSib) (toMaybe parent)
        pure $ RenderState { machine: machine', node: newNode }

removeChild
  :: forall eff o p g f s. RenderState s f g p o eff
  -> Eff (HalogenEffects eff) Unit
removeChild (RenderState { node }) = do
  npn <- DOM.parentNode node
  traverse_ (\pn -> DOM.removeChild node pn) (toMaybe npn)

substInParent
  :: forall eff
   . DOM.Node
  -> Maybe DOM.Node
  -> Maybe DOM.Node
  -> Eff (dom :: DOM | eff) Unit
substInParent newNode (Just sib) (Just pn) = void $ DOM.insertBefore newNode sib pn
substInParent newNode Nothing (Just pn) = void $ DOM.appendChild newNode pn
substInParent _ _ _ = pure unit

foreign import nodeRefEq :: DOM.Node -> DOM.Node -> Boolean
